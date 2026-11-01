--[[
 sim_vcu.lua  仿真用底盘 VCU（只在 SITL 中使用，实车用 vcu_can.lua）

 SITL 没有 CAN 总线，这个脚本代替 vcu_can.lua（garlic.15，Nav ↔ VCU CAN 通讯协议 v1.1）。
 对着 garlic.15 的 vcu_can.lua 照着写：遥测名和频率、STATUSTEXT 原文、作业请求（Work_On）的来源、
 HOLD 和解锁检查条件都和 vcu_can.lua 一致，只把 "CAN 收发" 换成下面的本地模拟：
   NavSta  OpSource = SVCU_MODE，SVCU_MUTE=1 时整帧丢失（NavSta lost），WorkFb 按下面的序列模拟，
           HsErr = SVCU_FAULT 为 0x11~0x16 时的低位
   HealthSta  Sys_Fault = SVCU_FAULT 为 1~7 时的值（SVCU_ESTOP=1 时为 1 急停），
           驱动器故障 = SVCU_FAULT 为 0x100+ 时的低位；电量 SVCU_SOC（SVCU_BAT=0 时不发 HealthSta）
   MotionSta  不模拟（SITL 车速即实际车速），反馈超时 / failsafe 不会出现
   RTK 检查不模拟（SITL 的 GPS 不是 RTK 固定解）

 地面站收到的（与 vcu_can.lua 相同）：
   NAMED_VALUE_FLOAT 5 Hz：VCU_MODE, VCU_FAULT, VCU_OK；VCU_BATV, VCU_SOC（仅 HealthSta 新鲜时）
   VCU_WORKFB：变化时立即发，之后 1 Hz（NavSta 无效时不发）
   VCU_WREQ：作业请求变化时立即发；VCU_WORK_EN=1 时随 VCU_WORKFB 1 Hz 补发
   STATUSTEXT："VCU: ..." 英文原文

 作业请求：VCU_WORK_EN=1 且已授权时，Work_On 跟随 SCRIPTING1（RC 辅助功能 300）的电平请求，
   地面站 / 航线用 MAV_CMD_DO_AUX_FUNCTION(300, 2=升杆作业 / 0=收杆) 下发；失权时请求清零。
   VCU_WORK_EN 与 vcu_can.lua 同名同义（参数表 VCU_，序号 10，默认 0）。

 WorkFb 模拟（SVCU_WFB_EN=1 时）：
   Work_On 0→1：1（升降杆中）持续 SVCU_WFB_T 秒 → 3（作业中）
   Work_On 1→0：1 持续 SVCU_WFB_T 秒 → 0（运输就绪）
   SVCU_WFB_FLT=1：下一次动杆到时不到位，变成 4（升降超时故障），之后自动清回 0（只注入一次）；
     4 一直保持到下一次 Work_On 变化（重新动杆）
   SVCU_WFB_EN=0：恒发 0（模拟 VCU 还没启用 WorkFb，协议：激活前 byte4 恒 0）
   SVCU_WFB_FRC：0~4 = 强制 WorkFb 为该值（行驶中强制 1 / 4 看切 HOLD），-1 = 不强制

 仿真参数（地面站不能改，用 sim_ctl.py：set SVCU_FAULT 7）：
   SVCU_FAULT   故障码：1~7 Sys_Fault（1 急停 2 链路断 3 FCU 超时 4 电池低温 5 电池高温 6 电量低
                7 提升超时，禁止解锁 / 行驶中切 HOLD）；0x11~0x16 HsErr（只上报）；0x100+ 驱动器（只上报）
   SVCU_MUTE    1 = NavSta 丢失（通信中断；行驶中切 HOLD）
   SVCU_MODE    OpSource：0 遥控 / 1 切换中 / 2 无人（非 2 时禁止解锁）
   SVCU_ESTOP   1 = 急停（上报为 Sys_Fault=1）
   SVCU_SOC     起始电量 %（解锁后每分钟下降 SVCU_DRAIN %）
   SVCU_DRAIN   每分钟耗电 %
   SVCU_BAT     1 = 发电量 VCU_SOC / VCU_BATV（默认）；0 = 不发（模拟收不到 HealthSta 的车）
   SVCU_WFB_EN  1 = 上报 WorkFb 序列（默认）；0 = 恒发 0
   SVCU_WFB_T   动杆时间（秒），默认 5
  SVCU_HS_T    授权后等遥控器 Ready 的时间（秒），默认 1（测地面站“请先按 Ready”时调大）
   SVCU_WFB_FLT 1 = 下一次动杆超时后变成 4
   SVCU_WFB_FRC -1 = 不强制（默认）；0~4 = 强制 WorkFb
--]]

local LOOP_MS = 20
local AUX_WORK = 300          -- 作业请求: RC 辅助功能 SCRIPTING1 (同 vcu_can.lua)
local WORK_LIFT_EXPECT_MS = 30000  -- Work_On 变化后多久内的升/降杆算我方请求的 (同 vcu_can.lua)
local SCRIPT_VERSION = "sim"

local MAV_EMERG, MAV_CRIT, MAV_WARN, MAV_INFO = 0, 2, 4, 6
local MODE_HOLD = 4
local DRIVE_MODES = { [5] = true, [10] = true, [11] = true, [12] = true, [15] = true }  -- LOITER AUTO RTL SMART_RTL GUIDED

local OP_NAV = 2
local HS_WAIT_START, HS_DONE = 2, 3
local WFB_TRANSPORT, WFB_LIFTING, WFB_WORKING, WFB_LIFT_FAULT = 0, 1, 3, 4

---------------------------------------------------------------------------
-- 参数: VCU_WORK_EN / VCU_ENABLE / VCU_RTK_REQ 与 vcu_can.lua 同表同序号 (SITL 里不跑 vcu_can.lua,
-- 表 71 空着)。ENABLE / RTK_REQ 只给地面站读 (它的开车前检查跟着这两个参数), 这里不起作用
---------------------------------------------------------------------------
assert(param:add_table(71, "VCU_", 12), "VCU: could not add param table")
assert(param:add_param(71, 1, "ENABLE", 1), "VCU: could not add param ENABLE")
assert(param:add_param(71, 7, "RTK_REQ", 2), "VCU: could not add param RTK_REQ")
assert(param:add_param(71, 10, "WORK_EN", 0), "VCU: could not add param WORK_EN")
local VCU_WORK_EN = Parameter("VCU_WORK_EN")

-- 仿真参数 SVCU_* (序号 1~7 与旧版一致)
local KEY = 72
assert(param:add_table(KEY, "SVCU_", 12), "SVCU: could not add param table")
local function p(name, idx, default)
  assert(param:add_param(KEY, idx, name, default), "SVCU: could not add param " .. name)
  return Parameter("SVCU_" .. name)
end
local FAULT   = p("FAULT", 1, 0)
local MUTE    = p("MUTE", 2, 0)
local MODE    = p("MODE", 3, 2)
local ESTOP   = p("ESTOP", 4, 0)
local SOC0    = p("SOC", 5, 85)
local DRAIN   = p("DRAIN", 6, 0.5)
local BAT     = p("BAT", 7, 1)
local WFB_EN  = p("WFB_EN", 8, 1)
local WFB_T   = p("WFB_T", 9, 5)
local WFB_FLT = p("WFB_FLT", 10, 0)
local WFB_FRC = p("WFB_FRC", 11, -1)
local HS_T    = p("HS_T", 12, 1)

local auth_id = arming:get_aux_auth_id()

---------------------------------------------------------------------------
-- 模拟的 VCU 帧 (代替 read_frames)
---------------------------------------------------------------------------
local navsta = { valid = false, op = 0, hs = 0, err = 0, wfb = 0 }
local health = { fresh = false, soc = 0, bat_v = 0, drv = 0, sys = 0 }

local soc = SOC0:get()
local last_soc0 = soc
local hs_done_ms = 0          -- 授权后约 1 s 模拟遥控器按 Ready (HandoverState 2 -> 3)

-- WorkFb 序列: 模拟的推杆位置 (VCU 内部), 按 Work_On 的变化动杆
local lift = { state = WFB_TRANSPORT, target = WFB_TRANSPORT, until_ms = 0 }
local prev_sim_work_on = false

local function simulate(now, work_on)
  local fault, mute, mode = FAULT:get(), MUTE:get(), MODE:get()
  navsta.valid = mute == 0
  navsta.op = math.floor(mode)
  local code = math.floor(fault)
  navsta.err = (code >= 0x11 and code <= 0x16) and (code - 0x10) or 0
  -- 授权握手: OpSource 变 2 时先 "等遥控器启动", SVCU_HS_T 秒 (默认 1) 后 "已启动"
  if navsta.op == OP_NAV then
    if navsta.hs ~= HS_WAIT_START and navsta.hs ~= HS_DONE then
      navsta.hs = HS_WAIT_START
      hs_done_ms = now + math.floor(HS_T:get() * 1000)
    elseif navsta.hs == HS_WAIT_START and now >= hs_done_ms then
      navsta.hs = HS_DONE
    end
  else
    navsta.hs = 0
  end

  -- 推杆: Work_On 变化时开始动杆, SVCU_WFB_T 秒后到位 (或注入的超时故障)
  if work_on ~= prev_sim_work_on then
    prev_sim_work_on = work_on
    lift.state = WFB_LIFTING
    lift.target = work_on and WFB_WORKING or WFB_TRANSPORT
    lift.until_ms = now + math.max(WFB_T:get(), 0) * 1000
  end
  if lift.state == WFB_LIFTING and now >= lift.until_ms then
    if WFB_FLT:get() > 0 then
      lift.state = WFB_LIFT_FAULT
      WFB_FLT:set(0)              -- 只注入一次
    else
      lift.state = lift.target
    end
  end
  local wfb = lift.state
  if WFB_EN:get() <= 0 then wfb = 0 end
  local frc = math.floor(WFB_FRC:get())
  if frc >= 0 and frc <= 4 then wfb = frc end
  navsta.wfb = wfb

  -- HealthSta
  health.fresh = BAT:get() ~= 0
  health.sys = ESTOP:get() ~= 0 and 1 or ((code >= 1 and code <= 7) and code or 0)
  health.drv = code >= 0x100 and (code - 0x100) or 0
  if SOC0:get() ~= last_soc0 then
    last_soc0 = SOC0:get()
    soc = last_soc0
  end
  if arming:is_armed() then
    soc = math.max(0, soc - DRAIN:get() * LOOP_MS / 60000)
  end
  health.soc = soc
  health.bat_v = 44 + 10 * soc / 100
  if not health.fresh then health.sys, health.drv = 0, 0 end
end

---------------------------------------------------------------------------
-- 以下与 vcu_can.lua (garlic.15) 的对应部分一致
---------------------------------------------------------------------------
-- MotionSta / HealthSta 反馈检查 (SITL 没有 MotionSta, 只看 HealthSta 故障码)
local function feedback_ok()
  if health.fresh and health.sys ~= 0 then
    return false, string.format("fault 0x%02X", health.sys)
  end
  return true, nil
end

-- 作业请求 (电平保持): SCRIPTING1 为 HIGH 时请求 Work_On=1; 从未设置过为 nil, 按 0
local function work_request()
  local pos = rc:get_aux_cached(AUX_WORK)
  return pos ~= nil and pos >= 2
end

-- WorkFb 检查: 升/降杆中或提升故障时 VCU 行驶锁 0, 禁止解锁 / 行驶中切 HOLD
local function workfb_block()
  if navsta.wfb == WFB_LIFTING then return "lift moving" end
  if navsta.wfb == WFB_LIFT_FAULT then return "lift fault" end
  return nil
end

local function ahrs_fwd_speed()
  local gs = ahrs:groundspeed_vector()
  local yaw = ahrs:get_yaw_rad()
  return gs:x() * math.cos(yaw) + gs:y() * math.sin(yaw)
end

local last_gcs_ms = 0
local last_warn_ms = 0
local last_wfb_ms = 0
local prev_hs = 0
local prev_wfb = 0
local prev_work_req = false
local prev_work_on = false
local last_work_change_ms = -100000
local was_authorized = false
local work_on = false

local function update()
  local now = millis():toint()
  simulate(now, work_on)

  local navsta_valid = navsta.valid
  local authorized = navsta_valid and navsta.op == OP_NAV

  -- 握手状态边沿提示
  if navsta_valid and navsta.hs ~= prev_hs then
    if navsta.hs == HS_WAIT_START then
      gcs:send_text(MAV_INFO, "VCU: wait RC start")
    elseif navsta.hs == HS_DONE then
      gcs:send_text(MAV_INFO, "VCU: RC start OK")
    end
  end
  if navsta_valid then prev_hs = navsta.hs end

  -- WorkFb 边沿提示 + 遥测: 变化时立即发 VCU_WORKFB, 之后 1 Hz
  if navsta_valid then
    local wfb_changed = navsta.wfb ~= prev_wfb
    if wfb_changed then
      if prev_wfb == WFB_LIFT_FAULT then gcs:send_text(MAV_INFO, "VCU: lift fault cleared") end
      if navsta.wfb == WFB_LIFTING then
        gcs:send_text(MAV_WARN, "VCU: lift moving")
      elseif navsta.wfb == WFB_LIFT_FAULT then
        gcs:send_text(MAV_CRIT, "VCU: lift fault")
      end
      prev_wfb = navsta.wfb
    end
    if wfb_changed or now - last_wfb_ms >= 1000 then
      last_wfb_ms = now
      gcs:send_named_float("VCU_WORKFB", navsta.wfb)
      if VCU_WORK_EN:get() > 0 then gcs:send_named_float("VCU_WREQ", work_request() and 1 or 0) end
    end
  end

  local fb_ok, fb_why = feedback_ok()
  local wfb_why = workfb_block()

  -- 解锁前检查: 已授权 + 提杆不在动作/故障 + VCU 反馈正常
  if auth_id then
    if not navsta_valid then arming:set_aux_auth_failed(auth_id, "VCU: NavSta lost")
    elseif not authorized then arming:set_aux_auth_failed(auth_id, "VCU: not authorized")
    elseif wfb_why then arming:set_aux_auth_failed(auth_id, "VCU: " .. wfb_why)
    elseif not fb_ok then arming:set_aux_auth_failed(auth_id, "VCU: " .. fb_why)
    else arming:set_aux_auth_passed(auth_id) end
  end

  -- 行驶中保护: 失权/升降杆/反馈异常 -> 切 HOLD
  local ok = navsta_valid and authorized and wfb_why == nil and fb_ok
  local why = fb_why
  if not navsta_valid then why = "NavSta lost"
  elseif not authorized then why = "not authorized"
  elseif wfb_why then why = wfb_why end

  local armed = arming:is_armed()
  local mode = vehicle:get_mode()
  local driving = armed and DRIVE_MODES[mode] == true
  if driving and not ok then
    vehicle:set_mode(MODE_HOLD)
    -- 我方请求的升/降杆 (Work_On 刚变过) 或静止时升/降杆, 只切 HOLD 不报警
    local expected = now - last_work_change_ms < WORK_LIFT_EXPECT_MS
    local still = math.abs(AR_AttitudeControl:get_desired_speed()) < 0.05
                  and math.abs(ahrs_fwd_speed()) < 0.1
    if not (why == "lift moving" and (expected or still)) and now - last_warn_ms > 2000 then
      gcs:send_text(MAV_WARN, "VCU: " .. why .. ", HOLD")
      last_warn_ms = now
    end
  end

  -- 作业 (Work_On): 失权时清掉请求, 恢复授权后保持 0, 由地面站重新下发
  if was_authorized and not authorized and work_request() then
    rc:run_aux_function(AUX_WORK, 0)
    gcs:send_text(MAV_WARN, "VCU: work request cleared")
  end
  local work_req = work_request()
  work_on = VCU_WORK_EN:get() > 0 and authorized and work_req
  if work_on ~= prev_work_on then
    prev_work_on = work_on
    last_work_change_ms = now
  end
  if work_req ~= prev_work_req then
    prev_work_req = work_req
    gcs:send_named_float("VCU_WREQ", work_req and 1 or 0)
  end
  was_authorized = authorized

  -- 5Hz 上报地面站
  if now - last_gcs_ms >= 200 then
    last_gcs_ms = now
    gcs:send_named_float("VCU_MODE", (not navsta_valid) and 0 or (navsta.op == OP_NAV and 2 or 1))
    local fault_code = 0
    if health.fresh and health.sys > 0 then
      fault_code = health.sys
    elseif navsta_valid and navsta.err > 0 then
      fault_code = 0x10 + navsta.err
    elseif health.fresh and health.drv > 0 then
      fault_code = 0x100 + health.drv
    end
    gcs:send_named_float("VCU_FAULT", fault_code)
    if health.fresh then
      gcs:send_named_float("VCU_BATV", health.bat_v)
      gcs:send_named_float("VCU_SOC", health.soc)
    end
    gcs:send_named_float("VCU_OK", ok and 1 or 0)
  end

  return update, LOOP_MS
end

gcs:send_text(MAV_INFO, "VCU: CAN bridge loaded (Nav v1.1) " .. SCRIPT_VERSION)

local function protected_wrapper()
  local success, err = pcall(update)
  if not success then
    gcs:send_text(MAV_EMERG, "VCU: error " .. tostring(err))
    return protected_wrapper, 1000
  end
  return protected_wrapper, LOOP_MS
end

return protected_wrapper()
