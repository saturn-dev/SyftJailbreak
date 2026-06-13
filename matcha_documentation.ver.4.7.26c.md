# Matcha LuaVM — Knowledge Base
> Compiled from session notes and tested scripts. Reflects all updates through latest test suites.

---

---

## What is Matcha

Matcha is an external executor/cheat tool for Roblox that emulates an internal executor through a VM layer. It runs Lua scripts externally but provides access to game internals like memory reading, input simulation, and drawing. It has its own UI framework for building tabs and menus that attach to Matcha's interface.

---

---

## Lua Standard Library Coverage

### Unsupported Syntax

- `goto` keyword — causes "Incomplete statement: expected assignment or a function call". Use `if/else` instead.
- Bitwise operators (`&`, `|`, `~`, `<<`, `>>`) — syntax error. Use `bit32` library.
- Floor division (`//`) — syntax error. Use `math.floor(a/b)`.
- Decimal literals like `14.4` in some positions — "Malformed number". Use `144/10` workaround.
- Scientific notation (`1e10`) in some contexts — "Malformed number". Use plain integers.

---

### pcall / error — Critical Behaviour

`error()` called explicitly does **not** get caught by `pcall`. It prints bare to the console and pcall returns `true` with a nil error object. Only VM-level errors are catchable.

```lua
-- VM errors ARE caught correctly
local ok, err = pcall(function() local x = nil; return x.y end)
-- ok = false, err = "Matcha:N: attempt to index nil with 'y'"

-- Explicit error() is NOT caught
local ok, err = pcall(function() error("something went wrong") end)
-- ok = true, err = nil  (wrong! message prints to console instead)

-- WORKAROUND: use a return-value pattern instead
local function safeOp()
    if somethingBad then return nil, "something went wrong" end
    return result
end
local val, err = safeOp()
if not val then -- handle err end
```

`xpcall` is similarly broken — the message handler never fires and return value is always nil.

`assert()` **does** work correctly — it is caught by pcall and returns a proper error string:

```lua
-- assert() IS caught by pcall
local ok, err = pcall(function() assert(false, "msg") end)
-- ok = false, err = "Matcha:N: msg"

-- Use assert for validation instead of error():
local function requireInstance(v)
    assert(typeof(v) == "Instance", "expected Instance, got " .. typeof(v))
    return v
end
```

### loadstring — Correct Behaviour

`loadstring` returns a function that executes, but `return` statements inside the chunk are silently dropped. Syntax errors do not return `nil, err` — they return a function that errors when called.

```lua
-- WRONG — return value is always nil
local f = loadstring("return 42")
local val = f()  -- nil

-- CORRECT — use _G as a side channel
_G.__result = nil
local f = loadstring("_G.__result = 42")
f()
local val = _G.__result  -- 42
_G.__result = nil  -- clean up

-- ALSO CORRECT — define a function in the chunk
_G.__fn = nil
local f = loadstring("_G.__fn = function(x) return x * 2 end")
f()
local result = _G.__fn(21)  -- 42
_G.__fn = nil
```

`setfenv` on a loadstring chunk **crashes** — use the `_G` write pattern instead.

---

## CFrame

CFrame is now a table global with several constructors working. **Not fully implemented** — several constructors crash.

### What Works

```lua
-- Constructors
CFrame.new()                                              -- identity CFrame
CFrame.new(x, y, z)                                       -- translation only
CFrame.new(x,y,z, r00,r01,r02, r10,r11,r12, r20,r21,r22) -- full 12-component form
CFrame.Angles(rx, ry, rz)                                 -- rotation only
CFrame.lookAt(position, target)                           -- look-at

-- Properties
cf.X, cf.Y, cf.Z          -- position components
cf.Position               -- Vector3
cf.LookVector             -- Vector3
cf.UpVector               -- Vector3
cf.RightVector            -- Vector3

-- Methods
cf:Lerp(cf2, t)           -- returns CFrame
cf:Inverse()              -- returns CFrame
cf:ToEulerAnglesXYZ()     -- returns rx, ry, rz
cf:GetComponents()        -- returns 12 numbers
cf:PointToWorldSpace(v3)  -- returns Vector3
cf:PointToObjectSpace(v3) -- returns Vector3
cf:VectorToWorldSpace(v3) -- returns Vector3

-- Arithmetic
cf * cf2    -- CFrame
cf * v3     -- Vector3

-- Instance property
hrp.CFrame              -- now returns CFrame (was nil before)
hrp.CFrame = newCFrame  -- write works
```

### What Does NOT Work

```lua
CFrame.new(position, lookAtPosition)   -- CRASHES (2 Vector3 args)
CFrame.fromEulerAnglesXYZ(rx, ry, rz)  -- nil / crashes
CFrame.fromEulerAnglesYXZ(rx, ry, rz)  -- nil / crashes
CFrame.fromMatrix(pos, vX, vY, vZ)     -- nil / crashes
CFrame.identity                        -- nil
cf:ToEulerAnglesYXZ()                  -- CRASHES
cf:ToObjectSpace(cf2)                  -- CRASHES
cf:ToWorldSpace(cf2)                   -- CRASHES
```

### 12-Component Form Replaces fromMatrix

`CFrame.new(x,y,z, r00…r22)` takes position then a row-major 3×3 rotation matrix. The third row is the **back** vector (negative LookVector).

```lua
-- CFrame.fromMatrix(pos, vRight, vUp, vBack) equivalent:
local cf = CFrame.new(
    pos.X, pos.Y, pos.Z,
    vRight.X, vRight.Y, vRight.Z,
    vUp.X,    vUp.Y,    vUp.Z,
    vBack.X,  vBack.Y,  vBack.Z   -- vBack = -LookVector
)

-- Identity CFrame at position:
local cf = CFrame.new(x, y, z,  1,0,0,  0,1,0,  0,0,1)
```

### fromEulerAnglesYXZ Workaround

```lua
-- Pure yaw rotation
local cf = CFrame.Angles(0, yawRadians, 0)

-- Full rotation with specific axis order — chain multiplications
local cf = CFrame.Angles(rx, 0, 0) * CFrame.Angles(0, ry, 0) * CFrame.Angles(0, 0, rz)
```

### Common Patterns

```lua
-- Rotate player to face a yaw angle
local rx, ry, rz = hrp.CFrame:ToEulerAnglesXYZ()
hrp.CFrame = CFrame.new(hrp.CFrame.X, hrp.CFrame.Y, hrp.CFrame.Z)
           * CFrame.Angles(0, newYaw, 0)
-- NOTE: CFrame.new(x,y,z) without rotation resets rotation to identity.
-- Always multiply by a rotation component.

-- Look at a target
hrp.CFrame = CFrame.lookAt(hrp.Position, targetPosition)

-- Offset 5 units in front
local frontCF = hrp.CFrame * CFrame.new(0, 0, -5)

-- Shift position while preserving rotation
hrp.CFrame = hrp.CFrame + Vector3.new(0, 5, 0)

-- Extract yaw
local _, ry, _ = hrp.CFrame:ToEulerAnglesXYZ()
local yawDegrees = math.deg(ry)
```

### Memory-Based CFrame Rotation (legacy workaround — still needed for fromMatrix / fromEulerAnglesYXZ)

The only way to set an exact rotation matrix without recomputing Euler angles, or for any crashed constructor:

```lua
-- Fetch offsets from external JSON (game-version-specific)
local HttpService = game:GetService("HttpService")
local response = game:HttpGet("https://offsets.ntgetwritewatch.workers.dev/offsets.json")
local offsets = HttpService:JSONDecode(response)

local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
local primitive = memory_read("uintptr", hrp.Address + offsets.Primitive)

-- Convert yaw degrees to rotation matrix components
local yawDegrees = 90
local yaw = yawDegrees * math.pi / 180
local fx = math.cos(yaw)
local fz = math.sin(yaw)

local r00=-fz  local r01=0  local r02=-fx
local r10=0    local r11=1  local r12=0
local r20=fx   local r21=0  local r22=-fz

local cf  = offsets.CFrame
local vel = offsets.Velocity

local px = memory_read("float", primitive + offsets.Position)
local py = memory_read("float", primitive + offsets.Position + 0x4)
local pz = memory_read("float", primitive + offsets.Position + 0x8)

for i = 1, 10000 do
    memory_write("float", primitive + cf + 0x00, r00)
    memory_write("float", primitive + cf + 0x04, r01)
    memory_write("float", primitive + cf + 0x08, r02)
    memory_write("float", primitive + cf + 0x0C, r10)
    memory_write("float", primitive + cf + 0x10, r11)
    memory_write("float", primitive + cf + 0x14, r12)
    memory_write("float", primitive + cf + 0x18, r20)
    memory_write("float", primitive + cf + 0x1C, r21)
    memory_write("float", primitive + cf + 0x20, r22)
    memory_write("float", primitive + cf + 0x24, px)
    memory_write("float", primitive + cf + 0x28, py)
    memory_write("float", primitive + cf + 0x2C, pz)
    memory_write("float", primitive + vel + 0x0, 0)
    memory_write("float", primitive + vel + 0x4, 0)
    memory_write("float", primitive + vel + 0x8, 0)
end
```

### Reading LookVector from Memory (Killer Tracer / Remote Players)

Since `cam.CFrame` methods fail and CFrame.new(pos, lookAt) crashes, read the look vector directly:

```lua
-- Primitive pointer offset from HumanoidRootPart: 0x148
-- Rotation matrix floats (column-major): r02, r12, r22 = third column = look/back vector
local primPtr = memory_read("uintptr_t", hrp.Address + 0x148)
if type(primPtr) == "number" and primPtr > 0x100000 then
    local r02 = memory_read("float", primPtr + 0xC8)
    local r12 = memory_read("float", primPtr + 0xD4)
    local r22 = memory_read("float", primPtr + 0xE0)
    local lookVec = Vector3.new(-r02, -r12, -r22)  -- negate = forward
end
```

| Component | Offset |
|-----------|--------|
| r02 (look X) | `primPtr + 0xC8` |
| r12 (look Y) | `primPtr + 0xD4` |
| r22 (look Z) | `primPtr + 0xE0` |

### CFrame Equality Is Reference-Based

```lua
CFrame.new(1,2,3) == CFrame.new(1,2,3)  -- false (different objects)
local cf = CFrame.new(1,2,3)
cf == cf  -- true (same reference)
```

For value comparison use `GetComponents` or compare individual fields:

```lua
local function cfEqual(a, b, eps)
    eps = eps or 0.0001
    return math.abs(a.X - b.X) < eps
       and math.abs(a.Y - b.Y) < eps
       and math.abs(a.Z - b.Z) < eps
       and math.abs(a.LookVector.X - b.LookVector.X) < eps
       and math.abs(a.LookVector.Z - b.LookVector.Z) < eps
end
```

---

## Vector3

Full support as of the latest update. All methods now work.

### Full Working API

```lua
-- Construction
Vector3.new(x, y, z)  -- works
Vector3.new()         -- zero vector (0, 0, 0)
Vector3.zero          -- (0,0,0)
Vector3.one           -- (1,1,1)

-- Arithmetic
v + v2    v - v2    v * scalar    v / scalar    v * v2  -- component-wise
-v        -- unary negation (now works)
v == v2   v ~= v2

-- Properties
v.X, v.Y, v.Z   -- components
v.Magnitude      -- number
v.Unit           -- Vector3 (normalized) — .X etc. accessible

-- Methods
v:Dot(v2)             -- number
v:Cross(v2)           -- Vector3
v:Lerp(v2, t)         -- Vector3
v:Max(v2)             -- Vector3 (component-wise max)
v:Min(v2)             -- Vector3 (component-wise min)
v:Abs()               -- Vector3 — NOTE: method call, NOT property
v:Floor()             -- Vector3
v:Ceil()              -- Vector3
v:FuzzyEq(v2, eps)    -- bool
```

> **Warning:** `v.Abs` as a property **crashes** — always use `v:Abs()`.

```lua
tostring(Vector3.new(1, 2, 3))
-- "Vector3(1.0000, 2.0000, 3.0000)"
```

### Manual Math (no longer needed, kept for reference)

```lua
-- Manual dot product (use v:Dot now)
local dot = a.X*b.X + a.Y*b.Y + a.Z*b.Z

-- Manual normalize (use v.Unit now)
local mag = math.sqrt(v.X*v.X + v.Y*v.Y + v.Z*v.Z)
local ux, uy, uz = v.X/mag, v.Y/mag, v.Z/mag
```

---

## Vector2

Same implementation level as Vector3. All basic operations work; method availability matches.

### Working
```lua
Vector2.new(x, y)           -- works
v.X, v.Y                    -- works
v.Magnitude                 -- works
v.Unit                      -- property read works, but .X on result CRASHES
v + v2, v * scalar, v == v  -- works
Vector2.zero, Vector2.one   -- exist
```

### Broken
```lua
v:Dot(v2)    -- fails
v:Cross(v2)  -- fails
v:Lerp(v2, t) -- fails
```

Use manual math for these on Vector2.

---

## Color3

### Working
```lua
Color3.new(r, g, b)        -- 0-1 range
Color3.fromRGB(r, g, b)    -- 0-255 range
Color3.fromHSV(h, s, v)    -- works
Color3.fromHex("#RRGGBB")  -- works
c.R, c.G, c.B              -- component reads work
```

### Broken
```lua
c:Lerp(c2, t)  -- fails
c:ToHSV()      -- fails
c:ToHex()      -- fails
```

### Color3 Gotcha

`Color3.new()` takes 0–1 values. `Color3.fromRGB()` takes 0–255. `BrickColor.Color` returns 0–1 already — do **not** multiply by 255.

```lua
Color3.new(1, 1, 1)           -- white, correct
Color3.new(255, 255, 255)     -- WRONG
Color3.fromRGB(255, 255, 255) -- white, correct
torso.BrickColor.Color        -- already 0-1, use directly
```

### Manual Color Lerp

```lua
local function lerpColor(c1, c2, t)
    return Color3.fromRGB(
        math.floor(c1.R*255 + (c2.R*255 - c1.R*255) * t),
        math.floor(c1.G*255 + (c2.G*255 - c1.G*255) * t),
        math.floor(c1.B*255 + (c2.B*255 - c1.B*255) * t)
    )
end
```

---

## Memory Reading & Writing

Matcha exposes `memory_read` and `memory_write` in unsafe mode.

### Type Support

```lua
memory_read("byte",      addr)   -- ✓ single byte
memory_read("float",     addr)   -- ✓ float32
memory_read("double",    addr)   -- ✓ float64
memory_read("int",       addr)   -- ✓
memory_read("uint",      addr)   -- ✓
memory_read("int32",     addr)   -- ✓
memory_read("uint32",    addr)   -- ✓
memory_read("int64",     addr)   -- ✓
memory_read("uint64",    addr)   -- ✓
memory_read("uintptr",   addr)   -- ✓ pointer / address
memory_read("uintptr_t", addr)   -- ✓ identical to uintptr
memory_read("string",    addr)   -- ✓ string pointer
memory_read("bool",      addr)   -- ✗ FAILS

memory_write("float", addr, value)  -- write (same type strings apply)
```

### Safety

```lua
-- Always pcall memory reads — they can throw on bad addresses
local ok, val = pcall(memory_read, "float", addr)
if ok and val then ... end

-- Address guard — skip obviously invalid pointers
if not addr or addr <= 4096 then return nil end
```

> **Note:** Reads at addresses 0, 1, and 4096 do **not** throw — they succeed (returning garbage values). The `addr <= 4096` guard is a safety convention, not enforced by the API. Keep it in your code regardless.

> **Note:** Writing to an invalid address fails silently without crashing Matcha.

`getbase()` — confirmed working, returns the Roblox base address as a non-zero number.

### Confirmed Working Offsets (version-6776addb8fbc4d17)

```lua
local VISIBLE_OFFSET = 1461   -- GuiObject.Visible (byte)
local SOUNDID_OFFSET = 224    -- Sound.SoundId (string ptr)
local VALUE_OFFSET   = 208    -- Misc.Value (float)

local INST = {
    ClassDescriptor = 24,
    ClassName       = 8,
    Name            = 176,
    ChildrenStart   = 120,   -- was 112 in older versions
    ChildNode       = 8,
}


local HUM = {
    Health       = 404,
    MaxHealth    = 436,  -- also readable at 408 (exact purpose of duplicate unclear)
    JumpHeight   = 428,  -- 7.2 default
    JumpPower    = 432,  -- 50.0 default
    AutoRotate   = 420,  -- 1.0 = enabled, 0.0 = disabled (float)
    WalkSpeed    = 468,  -- 16.0 default  ⚠ DANGEROUS if moving — see physics validation section
}

local CAM = {
    ViewportSize = 744,
}

local GUI = {
    AbsolutePosition = 272,
    AbsoluteSize     = 280,
}
```

### Humanoid Health via Memory

More reliable for remote players than the Instance API:

```lua
local function getHealthFromAddr(humanoid)
    local addr = tonumber(humanoid.Address)
    if not addr or addr <= 4096 then
        return humanoid.Health, humanoid.MaxHealth
    end
    local okH, health    = pcall(memory_read, "float", addr + HUM.Health)
    local okM, maxHealth = pcall(memory_read, "float", addr + HUM.MaxHealth)
    if okH and okM and health and maxHealth then
        return health, maxHealth
    end
    return humanoid.Health, humanoid.MaxHealth
end
```

### GUI Visibility via Memory

```lua
local function isGuiVisible(guiObject)
    local addr = tonumber(guiObject.Address)
    if not addr or addr <= 4096 then return false end
    local ok, byte = pcall(memory_read, "byte", addr + VISIBLE_OFFSET)
    return ok and byte ~= 0
end
```

### Sound ID Reading via Memory

```lua
local function readSoundId(soundObject)
    local addr = tonumber(soundObject.Address)
    if not addr or addr <= 4096 then return nil end
    local strPtr = readPtr(addr + SOUNDID_OFFSET)
    if not strPtr then return nil end
    local s = readStr(strPtr)
    if not s then return nil end
    return s:match("%d+")  -- extract numeric ID
end
```

---

## Task Library

```lua
task.spawn   -- ✓
task.wait    -- ✓ (timing accurate: 0.05s wait ≈ 0.0504s actual)
task.delay   -- ✓
task.defer   -- ✓
task.cancel  -- ✗ nil, does not exist

spawn        -- ✓ (legacy)
wait         -- ✓ (legacy)
delay        -- ✗ nil (legacy; use task.delay instead)
```

Since `task.cancel` doesn't exist, use a flag to cancel delayed calls:

```lua
local cancelled = false
task.delay(5, function()
    if cancelled then return end
    -- do thing
end)
-- later:
cancelled = true
```

Matcha uses `_COROUTINES` to track coroutines created via `task.spawn`. Entries are **not removed when coroutines finish** — it accumulates over time.

---

## Loop Patterns

### task.spawn + task.wait (polling, non-frame-synced)

```lua
local running = true
task.spawn(function()
    while running do
        task.wait(0.05)  -- 20hz
        -- your code
    end
end)

-- Stop it
running = false
```

### RunService (frame-synced — preferred)

```lua
local RS = game:GetService("RunService")

-- Heartbeat (~10Hz, physics rate)
local conn = RS.Heartbeat:Connect(function(dt)
    -- dt = elapsed time since last heartbeat (~0.1s)
end)

-- RenderStepped (~63Hz, render rate)
local conn = RS.RenderStepped:Connect(function(dt)
    -- dt = number
end)

-- To stop:
conn:Disconnect()  -- from OUTSIDE the callback only
```

> `task.wait()` with no argument = one frame (~0.016s at 60fps).
> `os.clock()` for timing.
> No `goto` keyword — use nested ifs instead.
> No `Enum.HumanoidStateType` — enums not available.

---

## RunService

All three events connect, disconnect, and fire. Confirmed rates over 300ms:

| Event | Count / 300ms | dt param |
|---|---|---|
| `Heartbeat` | ~3 | `number` (~0.097s) |
| `RenderStepped` | ~19 | `number` |
| `Stepped` | ~3 | first = elapsed time `number`, second = **nil** |

### ⚠ Disconnect From Inside Callback CRASHES

```lua
-- BROKEN — conn is nil inside the callback at capture time
local conn
conn = RS.Heartbeat:Connect(function()
    conn:Disconnect()  -- CRASHES
end)

-- CORRECT — use a flag instead
local running = true
local conn = RS.Heartbeat:Connect(function(dt)
    if not running then return end
    -- your code
end)
-- To stop: running = false  (or conn:Disconnect() from outside)
```

### RunService Methods — All Crash

```lua
RS:IsClient()   -- CRASHES
RS:IsServer()   -- CRASHES
RS:IsRunMode()  -- CRASHES
RS:IsStudio()   -- CRASHES
```

Only use the signal events (`Heartbeat`, `RenderStepped`, `Stepped`). Never call RunService methods.

---

## Input System

### VK Codes (Windows Virtual Key codes)

```lua
-- Mouse
0x01  -- LMB
0x02  -- RMB
0x04  -- MMB

-- Letters (0x41-0x5A = A-Z)
0x41=A  0x42=B  0x43=C  0x44=D  0x45=E
0x46=F  0x47=G  0x48=H  0x49=I  0x4A=J
0x4B=K  0x4C=L  0x4D=M  0x4E=N  0x4F=O
0x50=P  0x51=Q  0x52=R  0x53=S  0x54=T
0x55=U  0x56=V  0x57=W  0x58=X  0x59=Y  0x5A=Z

-- Numbers (0x30-0x39 = 0-9)
0x30=0  0x31=1  0x32=2  0x33=3  0x34=4
0x35=5  0x36=6  0x37=7  0x38=8  0x39=9

-- Special
0x20  -- Space
0x0D  -- Enter

-- Function keys
0x70=F1  0x71=F2  0x72=F3  0x73=F4
```

### Input Functions

```lua
iskeypressed(vk)    -- returns bool (VK code)
keypress(vk)
keyrelease(vk)
mouse1press()
mouse1release()
mouse1click()
ismouse1pressed()
mouse2press()
mouse2release()
mouse2click()
ismouse2pressed()
mousemoverel(0, dx, dy)     -- requires leading 0 — crashes without it
mousemoveabs(0, x, y)       -- requires leading 0 — crashes without it
mousescroll(0, delta)       -- requires leading 0; positive = up, negative = down
```

> `mousemoveabs` and `mousemoverel` have **immediate visible effect** — the cursor moves on screen instantly.

### iskeypressed vs UIS:IsKeyDown

These use **different** key code systems:

```lua
-- iskeypressed uses Windows VK codes
iskeypressed(0x41)   -- A key (VK = 65)
iskeypressed(0x20)   -- Space (VK = 32)

-- UIS:IsKeyDown uses Roblox Enum.KeyCode values (which are just numbers)
UIS:IsKeyDown(Enum.KeyCode.A)      -- A key (Enum value = 1)
UIS:IsKeyDown(Enum.KeyCode.Space)  -- Space (Enum value = 31)
```

`Enum.KeyCode.A` returns a **number**, not an Enum object — no `.Name` or `.Value` properties. Full table: A–Z (1–26), Space (31), Enter (32), Escape (33), MouseButton1 (34), MouseButton2 (35), LeftShift (27), RightShift (28), LeftControl (29), RightControl (30).

### UIS Availability

```lua
UIS.InputBegan:Connect(fn)    -- ✓
UIS:IsKeyDown(Enum.KeyCode.A) -- ✓
Enum.KeyCode                  -- ✓ (table of numbers)
UIS:GetKeysPressed()          -- ✗ fails
UIS:GetMouseLocation()        -- ✗ fails
```

> **Note:** `UserInputService` is a **table**, not userdata — it's a partial shim. `input.KeyCode` in `InputBegan` returns raw VK integer.

---

## Drawing API

### Types

All four non-Text types work completely.

```lua
local line = Drawing.new("Line")
line.Thickness = 1
line.Color = Color3.fromRGB(255, 0, 0)
line.Visible = true
line.From = Vector2.new(0, 0)
line.To = Vector2.new(100, 100)

local circle = Drawing.new("Circle")
circle.Position = Vector2.new(x, y)
circle.Radius   = 10
circle.Filled   = false
circle.Color    = Color3.fromRGB(255, 255, 255)
circle.Visible  = true

local square = Drawing.new("Square")
square.Position = Vector2.new(x, y)
square.Size     = Vector2.new(w, h)
square.Filled   = false
square.Visible  = true

local tri = Drawing.new("Triangle")
tri.PointA = Vector2.new(x1, y1)
tri.PointB = Vector2.new(x2, y2)
tri.PointC = Vector2.new(x3, y3)
tri.Filled = false
tri.Visible = true

local text = Drawing.new("Text")
text.Font     = Drawing.Fonts.System  -- UI, System, SystemBold, Minecraft, Monospace, Pixel, Fortnite
text.Size     = 16
text.Text     = "hello"
text.Color    = Color3.fromRGB(255, 255, 255)
text.Outline  = true
text.Center   = true
text.Visible  = true
text.Position = Vector2.new(100, 100)
```

### Drawing.Text — Confirmed Quirks

- **`.Color` read always returns nil** — write works visually but reading the property back always returns nil. Same for all color properties on Text.
- **`.OutlineColor` write FAILS** — do not set it.
- **`.Center = true` works correctly for single-line text** — centers both horizontally and vertically around the position point.
- **`.Center = true` breaks with `\n` multiline text** — horizontal centering is miscalculated, lines appear slightly off-center. More lines = more shift. Newline characters are likely included in the width calculation.
- **Workaround for multiline** — use `Center = false` and calculate X manually, or use one Drawing.Text per line.

```lua
-- BROKEN — multiline + Center=true drifts sideways
text.Center = true
text.Text   = "line 1\nline 2\nline 3"

-- CORRECT — one object per line
local lines = {"line 1", "line 2", "line 3"}
for i, line in ipairs(lines) do
    local t = Drawing.new("Text")
    t.Font = Drawing.Fonts.System; t.Size = 16
    t.Color = Color3.fromRGB(255,255,255)
    t.Center = true
    t.Position = Vector2.new(cx, cy + (i-1) * 20)
    t.Text = line; t.Visible = true
end

-- Remove a drawing
drawing:Remove()
```

### WorldToScreen

```lua
-- Converts 3D world position to 2D screen position
local screenPos, onScreen = WorldToScreen(worldPos)
-- screenPos = Vector2, onScreen = bool
-- Always pcall — can throw if camera not ready
local ok, screenPos, onScreen = pcall(WorldToScreen, position)
```

### Drawing.Image

`Drawing.new("Image")` creates successfully. Base properties work (`Visible`, `Position`, `Size`, `Transparency`, `ZIndex`, `Color`, `Rounding`). Setting the image uses the `Data` property:

```lua
local img = Drawing.new("Image")
img.Position = Vector2.new(100, 100)
img.Size     = Vector2.new(200, 200)

-- Fetch image bytes and write directly
local bytes = game:HttpGet("https://example.com/image.png")
img.Data    = bytes
img.Visible = true
-- Silently fails with console message "Drawing.Image: failed to load image data" if bytes are invalid
```

Broken properties:
```lua
img.Image    -- CRASHES
img.Texture  -- CRASHES
img.Uri      -- CRASHES
img.Url      -- CRASHES
img.FlipX    -- nil
img.FlipY    -- nil
img.Rotation -- CRASHES on write
```

### ZIndex Layering Convention

| Layer | ZIndex | Content |
|-------|--------|---------|
| Card background | 50 | Filled squares/circles |
| Card border | 51 | Border lines |
| Content | 52 | Text, buttons |
| Button labels | 54 | On top of button fills |

---

## HTTP

### Working

```lua
game:HttpGet(url)                        -- ✓
game:HttpGet(url, headersTable)          -- ✓ headers are forwarded
game:HttpPost(url, body)                 -- ✓
game:HttpPost(url, body, contentType)    -- ✓
game:HttpPost(url, body, contentType, headersTable)  -- ✓

-- Examples
game:HttpGet(url, {
    ["X-Custom-Header"] = "value",
    ["Authorization"]   = "Bearer token",
    ["Accept"]          = "application/json"
})

game:HttpPost(
    "https://api.example.com/data",
    HttpService:JSONEncode({ key = "value" }),
    "application/json",
    { ["Authorization"] = "Bearer token" }
)

-- Lowercase global aliases
httpget(url)          -- identical to game:HttpGet
httppost(url, ...)    -- identical to game:HttpPost

HttpService:JSONEncode(t)
HttpService:JSONDecode(str)
HttpService:GenerateGUID(includeDashes)  -- returns 36-char string
```

### Not Available

```lua
HttpService:RequestAsync({...})  -- fails
```

---

## Services

| Service | Status |
|---------|--------|
| Players | ✓ userdata |
| Workspace | ✓ userdata |
| UserInputService | ✓ **table** (not userdata — partial shim) |
| HttpService | ✓ userdata |
| RunService | ✓ userdata |
| TweenService | ✓ userdata (but `TweenInfo.new` is nil — unusable) |
| ReplicatedStorage | ✓ userdata |
| MarketplaceService | ✓ userdata |
| BadgeService | ✓ userdata |
| Stats | ✓ userdata |
| DataStoreService | ✗ nil |
| VirtualInputManager | ✗ nil |

`RunService:IsClient()` and `IsServer()` both **crash** — do not call. Use events only.

---

## Events & Signals

```lua
Players.PlayerAdded:Connect(fn)    -- ✓
Players.PlayerRemoving:Connect(fn) -- ✓
lp.CharacterAdded:Connect(fn)      -- ✗ FAILS (confirmed broken)
lp.CharacterRemoving:Connect(fn)   -- ✗ FAILS
Signal:Once(fn)                    -- ✗ fails
Signal.Wait                        -- ✗ nil (not a method at all)
RS.Heartbeat:Connect(fn)           -- ✓
RS.RenderStepped:Connect(fn)       -- ✓
RS.Stepped:Connect(fn)             -- ✓
```

---

## Instance Methods

### Working
```lua
FindFirstChild, FindFirstChildOfClass, FindFirstChildWhichIsA  -- ✓
WaitForChild (with timeout)  -- ✓
GetChildren, GetDescendants  -- ✓
IsA, IsDescendantOf          -- ✓
GetFullName                  -- ✓
ClassName, Name, Parent      -- ✓ property reads
GetAttributes                -- ✓ returns table
```

### Broken
```lua
SetAttribute / GetAttribute  -- SetAttribute silently no-ops. GetAttribute returns nil regardless of type. Do not use.
Clone         -- fails
IsAncestorOf  -- fails
Destroy       -- untested
Instance.new  -- fails — cannot create new Roblox Instances
```

> `IsA()` can return unexpected values — always compare with `== true` explicitly.

---

## Players & LocalPlayer

```lua
lp.Name         -- ✓
lp.DisplayName  -- ✗ nil
lp.UserId       -- ✗ nil
lp.AccountAge   -- ✗ nil
lp.Team         -- ✗ nil
lp.TeamColor    -- ✗ nil

lp:GetMouse()    -- ✓
mouse.X, mouse.Y -- ✓ screen coordinates
mouse.Hit        -- ✗ nil
mouse.Target     -- ✗ nil
mouse.UnitRay    -- ✗ nil
```

> Most LocalPlayer properties beyond `.Name` are nil. Use the player dump pattern for AccountAge etc.

### Humanoid

```lua
hum.WalkSpeed    -- ✓ readable
hum.JumpPower    -- ✓ readable
hum.JumpHeight   -- ✓ readable
hum.AutoRotate   -- ✓ readable
hum.Health       -- ✓ readable (but use memory for reliability)

hum.WalkSpeed = x    -- ✗ write FAILS — use memory_write
hum.AutoRotate = x   -- ✗ write FAILS — use memory_write
hum:GetState()       -- ✗ FAILS on all humanoids
hum:GetPlayingAnimationTracks() -- ✗ FAILS on all humanoids
```

### What Replicates to Client vs What Doesn't

**DOES replicate (readable on other players):**
- Character model and all children (Parts, Attachments, Motor6Ds)
- Humanoid (Health, MaxHealth readable via memory)
- HumanoidRootPart.Position, Velocity
- StringValue, NumberValue, BoolValue, IntValue contents
- Instance names and class names

**DOES NOT replicate:**
- Animator children (AnimationTracks not visible via API)
- `Humanoid:GetState()` — fails on all
- `Humanoid:GetPlayingAnimationTracks()` — fails on all

---

## Camera

```lua
cam.ViewportSize   -- ✓ Vector2
cam.FieldOfView    -- ✓ number
cam.Position       -- ✓ Vector3 (camera world position)

cam.CFrame              -- ✗ nil
cam.Focus               -- ✗ nil
cam.CameraType          -- ✗ nil
cam.NearPlaneZ          -- ✗ nil
cam.DiagonalFieldOfView -- ✗ nil

cam:WorldToScreenPoint(v3)  -- ✗ FAILS — use global WorldToScreen() instead
cam:ScreenPointToRay(x, y)  -- ✗ FAILS
cam:ViewportPointToRay(x, y) -- ✗ FAILS
```

Only `ViewportSize`, `FieldOfView`, and `Position` are accessible. `cam.CFrame` is nil — use `hrp.CFrame.LookVector` as an approximation for camera direction, or read camera position from memory if `cam.Address` is available.

> Use the global `WorldToScreen(worldPos)` — never `cam:WorldToScreenPoint()`.

---

## File System

All filesystem functions confirmed working:

```lua
writefile(path, content)     -- ✓ saves to C:\matcha\workspace\
readfile(path)               -- ✓ (round-trip confirmed)
appendfile(path, content)    -- ✓
isfile(path)                 -- ✓ returns true/false correctly
isfolder(path)               -- ✓
makefolder(path)             -- ✓
listfiles(path)              -- ✓ returns table (confirmed working — remove old caveat)
delfile(path)                -- ✓ actually removes file
delfolder(path)              -- ✓
setclipboard(text)           -- ✓
```

---

## Matcha UI System

Full menu framework via the global `UI`.

```lua
UI.AddTab("Tab Name", function(tab)
    local sec = tab:Section("Section Name", "Left")   -- or "Right"
    local secTabbed = tab:Section("Name", "Left", {"Page 1", "Page 2"}, maxHeight)

    if secTabbed.page == 0 then ... end
    if secTabbed.page == 1 then ... end

    sec:Toggle("id", "Label", defaultBool, callback)
    sec:Keybind("id", 0x46, "toggle")   -- or "hold", "always", "click"
    sec:SliderInt("id", "Label", min, max, default, callback)
    sec:SliderFloat("id", "Label", min, max, default, "%.1f", callback)
    sec:Combo("id", "Label", {"Option1", "Option2"}, defaultIndex, callback)
    sec:Button("Label", callback)
    sec:Button("Label", width, height, callback)
    sec:InputText("id", "Label", default, callback)
    sec:ColorPicker("id", r, g, b, a, callback)
    sec:ColorPicker2("id1", {r,g,b,a}, "id2", {r,g,b,a}, callback)
    sec:Text("some text")
    sec:Tip("tooltip for previous widget")
    sec:Spacing()
end)

UI.RemoveTab("Tab Name")
UI.GetValue("id")       -- read any widget value
UI.SetValue("id", val)  -- write any widget value
```

### Keybind Widget Methods

```lua
local kb = sec:Keybind("id", 0x46, "toggle")
kb:IsActive()
kb:GetKey()
kb:SetKey(vk)
kb:GetKeyName()                            -- "f", "lmb", etc.
kb:GetType()                               -- "toggle", "hold", "always", "click"
kb:SetType(str)
kb:AddToHotkey("Label", "toggle_id")       -- show in hotkey overlay when toggle is ON
kb:RemoveFromHotkey()
```

### Combo Widget Methods

```lua
local c = sec:Combo("id", "Label", items)
c:Add("item")
c:Remove("item")
c:Clear()
c:GetItems()
c:GetText()
c:SetValue(index)
```

### Widget Value Types

| Widget | Value type |
|--------|-----------|
| Toggle | bool |
| SliderInt | int |
| SliderFloat | float |
| Combo | int (0-based) |
| InputText | string |
| ColorPicker | r, g, b, a |
| Keybind | bool |

### Notification

```lua
notify("message", "title", durationSeconds)
```

More reliable than `Drawing.new("Text")` which has a known rendering bug.

---

## UILib (External Library Pattern)

Some scripts load a full UI library from a remote URL instead of using the built-in `UI` global.

```lua
local LibPath = "C:/matcha/workspace/library.lua"
if not isfile(LibPath) then
    local src = game:HttpGet("https://raw.githubusercontent.com/catowice/p/refs/heads/main/library.lua")
    if src and type(src) == "string" and #src > 100 then
        writefile(LibPath, src)
    end
end
local UILib = require(LibPath)
```

### UILib API

```lua
UILib:SetWatermarkEnabled(false)
UILib:SetMenuTitle("Title")
UILib:SetMenuSize(Vector2.new(w, h))
UILib:CenterMenu()
UILib:Step()                            -- must be called every frame in main loop
UILib:Notification("message", seconds)
UILib:CreateSettingsTab("Settings")
UILib:RegisterActivity(function() return "status string" end)

local tab = UILib:Tab("Tab Name")
local sec = tab:Section("Section Name")

sec:Toggle("Label", default, callback)
sec:Slider("Label", default, step, min, max, "unit", callback)
sec:Dropdown("id", {default}, {options}, multiselect, callback)

local tog = sec:Toggle("Label", default, callback)
tog:AddColorpicker("Label", Color3, showAlpha, callback)

UILib.GetValue("id")
UILib.SetValue("id", val)
```

### Mouse Position Override

UILib may need its mouse position patched manually:

```lua
local ok, mouse = pcall(function() return Player:GetMouse() end)
UILib._GetMousePos = function(self)
    if ok and mouse then return Vector2.new(mouse.X, mouse.Y) end
    return Vector2.new(0, 0)
end
```

### Theme & Settings

```lua
UILib._theming.accent = Color3.fromRGB(255, 105, 180)

-- Remove unwanted Settings tab items
local menuItems = UILib._tree["Settings"]._items["Menu"]._items
menuItems[1].label = "Menu key"
table.remove(menuItems, 4)
table.remove(menuItems, 3)
table.remove(menuItems, 2)
```

### Main Loop with UILib

```lua
while true do
    UILib:Step()
    -- your per-frame logic
    task.wait()
end
```

### Launching a Script from UILib

```lua
task.spawn(loadstring(game:HttpGet(url .. "?cache=" .. tostring(os.time()))))
while true do task.wait(60) end   -- keep script alive
```

`task.spawn` wraps `loadstring` so errors don't crash the loader. The infinite `task.wait` loop keeps spawned threads alive.

---

## MemoryManager Module

Some scripts load a `MemoryManager` module from a remote URL.

```lua
local MemPath = "C:/matcha/workspace/Modules/MemoryManager.lua"
if not isfile(MemPath) then
    local src = game:HttpGet("https://raw.githubusercontent.com/thelucas128/Macha/refs/heads/main/MemoryManagerFixed.luau")
    if src and type(src) == "string" and #src > 100 then
        writefile(MemPath, src)
    end
end
local MemoryManager = require(MemPath)
```

### Confirmed Methods

```lua
MemoryManager.GetRotationMatrix(part)       -- returns rotation matrix table indexed [0]-[8]
MemoryManager.GetGuiObjectRotation(address) -- returns rotation angle of a GuiObject (degrees)
```

`GetRotationMatrix` returns a flat table with indices 0–8 (column-major 3×3):
- `[0],[3],[6]` = right vector components (X axis)
- `[1],[4],[7]` = up vector components (Y axis)
- `[2],[5],[8]` = look/back vector components (Z axis)

Always nil-check the result — returns nil if the part address is invalid.

---

## Roblox API — What's Not Available

```lua
TweenInfo.new        -- nil (TweenService accessible but unusable)
Enum.EasingStyle     -- nil
Enum.EasingDirection -- nil
Enum.HumanoidStateType -- nil
Enum.Material        -- nil
-- Only Enum.KeyCode is available

Ray.new              -- fails
workspace:Raycast    -- fails
workspace:FindPartOnRay -- fails
Random.new           -- fails
UDim2.new            -- fails
NumberRange.new      -- fails
Instance.new("Part") -- fails — cannot create new Instances
```

`PathfindingService` is accessible (userdata) but `CreatePath()` fails — same situation as TweenService. Cannot use Roblox pathfinding API at all.

`RemoteEvent` and `RemoteFunction` instances are accessible but none of their methods exist (`FireServer`, `OnClientEvent`, `InvokeServer` etc. all nil). Remote interaction is not currently possible from Matcha.

---

## Getting Ping

**Use `GetPingValue()`** — the Stats service workaround returns 0 in Matcha.

```lua
-- NEW — correct
local ping = GetPingValue()  -- returns ms as number, e.g. 114

-- OLD — broken in Matcha, returns 0, remove this
local function GetPing()
    local ok, v = pcall(function()
        return game:GetService("Stats").Network.ServerStatsItem["Data Ping"].Value
    end)
    return (ok and tonumber(v)) or 0
end
```

---

## Executor & Identity

```lua
identifyexecutor()   -- returns "Matcha", "1.0.0"
base64encode(str)    -- ✓ ("hello" → "aGVsbG8=")
base64decode(str)    -- ✓ (round-trip confirmed)
getbase()            -- ✓ returns non-zero number (Roblox base address)
getfflag(k)          -- ✓ returns "0" for unknown flags
setfflag(k, v)       -- ✗ THROWS — do not use
```

### run_secure / create_run_secure

Both take **base64-encoded Luau bytecode**, not Lua source strings:

```lua
-- run_secure executes compiled bytecode encoded as base64
local scripts  = getscripts()
local bytecode = getscriptbytecode(scripts[1])
local encoded  = base64encode(bytecode)
run_secure(encoded)

-- create_run_secure(name, base64_bytecode) — returns a string handle
```

`string.dump` does not exist in Matcha — use `getscriptbytecode` to obtain valid bytecode.

### RegisterModel

```lua
local handle = RegisterModel({ entry = someInstance })
-- handle.Remove()        -- unregister
-- handle.__entry_addr    -- memory address of the registered Instance
```

---

## Global Functions Reference

```lua
-- Type checking
typeof(value)         -- Roblox type names: "Vector3", "CFrame", "Instance", "number", etc.
                      -- Use typeof for Roblox objects, type() for Lua primitives

-- Timing
tick()                -- session uptime in seconds (NOT Unix time, NOT os.clock)
os.time()             -- Unix timestamp (use for real timestamps)
os.clock()            -- high-resolution timer

-- Window state
isrbxactive()         -- bool, true if Roblox window is focused

-- Logging
warn(...)             -- like print but visually distinct in Matcha console
printl(...)           -- alternative print
print(...)            -- standard

-- Game info
getgamename()         -- returns game name string, e.g. "[UP] Just a baseplate."

-- Memory
gcinfo()              -- current Lua memory usage in KB

-- Proxy objects
newproxy(hasMetatable) -- creates blank userdata; newproxy(true) gives editable metatable

-- Environment
getfenv(n)            -- returns environment of call stack level n or function
setfenv(fn, env)      -- sets environment of a function, returns the function
                      -- setfenv on loadstring chunks CRASHES — use _G pattern instead

-- HTTP aliases
httpget(url)          -- alias for game:HttpGet
httppost(url, ...)    -- alias for game:HttpPost

-- Misc
setrobloxinput(...)   -- exists; tested but purpose unknown. Does NOT block InputBegan, iskeypressed, or change isrbxactive(). Avoid calling with anything other than true/false.
create_run_secure(...)
RegisterModel(table)
errorl(fn)            -- exists, purpose unclear
```

### typeof vs type

```lua
type(Vector3.new())     -- "userdata"
typeof(Vector3.new())   -- "Vector3"
type(CFrame.new())      -- "userdata"
typeof(CFrame.new())    -- "CFrame"
type(player)            -- "userdata"
typeof(player)          -- "Instance"
typeof(1)               -- "number"   (same as type)
typeof("str")           -- "string"
```

### newproxy Pattern

```lua
local function makeInterface(methods)
    local proxy = newproxy(true)
    local mt = getmetatable(proxy)
    mt.__index = methods
    mt.__tostring = function() return "Interface" end
    return proxy
end

local obj = makeInterface({
    greet = function(self) return "hello" end
})
```

### getfenv / setfenv

```lua
-- Custom isolated environment
local env = { x = 42 }
local f = setfenv(function() return x end, env)
f()  -- 42

-- Environment with _G fallback
local env = setmetatable({}, { __index = _G })
env.myVar = 99
local f = setfenv(function() return myVar + GetPingValue() end, env)
f()  -- works

-- getfenv() in main thread returns _G
getfenv() == _G  -- true
```

---

## Additional Libraries

### bit32

Full Roblox `bit32` library available:

```lua
bit32.band(a, b, ...)          -- AND
bit32.bor(a, b, ...)           -- OR
bit32.bxor(a, b, ...)          -- XOR
bit32.bnot(a)                  -- NOT (32-bit unsigned result — bnot(0) = 4294967295)
bit32.lshift(a, n)             -- left shift
bit32.rshift(a, n)             -- right shift (logical)
bit32.arshift(a, n)            -- right shift (arithmetic)
bit32.lrotate(a, n)
bit32.rrotate(a, n)
bit32.btest(a, b)              -- true if AND result is non-zero
bit32.extract(n, field, width)
bit32.replace(n, v, field, width)
bit32.countlz(n)               -- count leading zeroes
bit32.countrz(n)               -- count trailing zeroes
bit32.byteswap(n)              -- reverse byte order
```

`bit32.band(addr, 0xFFFFFFFF)` clamps a number to 32-bit unsigned — useful before memory writes.

### buffer

Full Roblox buffer library for structured binary data:

```lua
local b = buffer.create(16)
buffer.writeu8(b, offset, value)    -- unsigned 8-bit
buffer.writeu16(b, offset, value)
buffer.writeu32(b, offset, value)
buffer.writei8(b, offset, value)    -- signed variants
buffer.writei16(b, offset, value)
buffer.writei32(b, offset, value)
buffer.writef32(b, offset, value)   -- float32
buffer.writef64(b, offset, value)   -- float64
buffer.writestring(b, offset, str)
buffer.writebits(b, offset, ...)
buffer.readu8(b, offset)            -- read back (same pattern for all types)
buffer.len(b)
buffer.copy(dst, dstOffset, src, srcOffset, count)
buffer.fill(b, offset, value, count)
buffer.tostring(b)
buffer.fromstring(str)
```

Use `buffer` for building multi-field memory write payloads.

### utf8

```lua
utf8.len(str)                  -- character count (not byte count)
utf8.char(codepoint, ...)      -- codepoint(s) to string
utf8.codepoint(str, i, j)      -- string to codepoint(s)
utf8.codes(str)                -- iterator over codepoints
utf8.offset(str, n)            -- byte offset of nth character
utf8.charpattern               -- pattern matching one UTF-8 character
```

### vector (native Luau type)

Significantly faster than `Vector3` for tight computation loops. Returns `vector` typed values — **not interoperable with `Vector3`**.

```lua
vector.create(x, y, z)    -- type = "vector", NOT "userdata"
vector.magnitude(v)
vector.normalize(v)
vector.dot(a, b)
vector.cross(a, b)
vector.abs(v)
vector.floor(v)
vector.ceil(v)
vector.sign(v)
vector.clamp(v, min, max)
vector.angle(a, b)
vector.min(a, b)
vector.max(a, b)
vector.zero
vector.one

-- Component access: both lowercase and uppercase work
local v = vector.create(1, 2, 3)
v.x  -- 1
v.X  -- 1 (also works)
```

**Performance comparison (100k iterations):**

| Operation | Time |
|-----------|------|
| `math.sqrt` (manual) | ~129ms |
| `Vector3.Magnitude` | ~49ms |
| `vector.magnitude` | ~6ms |
| `Vector3:Dot` | ~110ms |
| `vector.dot` | ~10ms |

Converting 100k `vector` → `Vector3` takes ~29ms. Convert only when required (e.g. `WorldToScreen`):

```lua
local vl  = vector.create(x, y, z)
local mag = vector.magnitude(vl)
local dir = vector.normalize(vl)

-- Convert to Vector3 only when required
local v3 = Vector3.new(vl.x, vl.y, vl.z)
local sc, on = WorldToScreen(v3)
```

### String Metatable Extensions

The string metatable is accessible and writable:

```lua
local mt = getmetatable("")
mt.__index.trim = function(s)
    return s:match("^%s*(.-)%s*$")
end
mt.__index.startsWith = function(s, prefix)
    return s:sub(1, #prefix) == prefix
end
mt.__index.split = function(s, sep)
    local parts = {}
    for part in s:gmatch("([^" .. sep .. "]+)") do
        table.insert(parts, part)
    end
    return parts
end

-- After adding: all strings have these methods
"  hello  ":trim()                 -- "hello"
"hello world":startsWith("hello")  -- true
```

Extensions persist for the entire script session — add them once at the top.

---

## ESP Patterns

### 3D Box ESP

```lua
local BoxEdges = {
    {1,2},{3,4},{1,3},{2,4},   -- bottom face
    {5,6},{7,8},{5,7},{6,8},   -- top face
    {1,5},{2,6},{3,7},{4,8}    -- vertical edges
}

local function GetCorners3D(part, pos)
    if not pos then return {} end
    local sx, sy, sz = part.Size.X/2, part.Size.Y/2, part.Size.Z/2
    local m = MemoryManager.GetRotationMatrix(part)
    local r = m and Vector3.new(m[0],m[3],m[6])*sx or Vector3.new(sx,0,0)
    local u = m and Vector3.new(m[1],m[4],m[7])*sy or Vector3.new(0,sy,0)
    local b = m and Vector3.new(m[2],m[5],m[8])*sz or Vector3.new(0,0,sz)
    return {
        pos-r+u+b, pos+r+u+b, pos-r-u+b, pos+r-u+b,
        pos-r+u-b, pos+r+u-b, pos-r-u-b, pos+r-u-b
    }
end

-- Per frame: project all 8 corners
local pts, allOn = {}, true
for c = 1, 8 do
    local sc, on = WorldToScreen(corners[c])
    if not on or not sc then allOn = false
    else pts[c] = Vector2.new(math.floor(sc.X+0.5), math.floor(sc.Y+0.5)) end
end
if allOn then
    for l = 1, 12 do
        local e = BoxEdges[l]
        lines[l].From, lines[l].To = pts[e[1]], pts[e[2]]
        lines[l].Visible = true
    end
end

-- Cache corners — only recompute when position changes
if pos ~= cache.CachedPos then
    cache.Corners = GetCorners3D(part, pos)
    cache.CachedPos = pos
end
```

### Circle ESP (3D Ground Ring)

```lua
local CircleSegments = 16
local CircleMults = {}
for i = 1, CircleSegments do
    local angle = (i / CircleSegments) * (math.pi * 2)
    CircleMults[i] = { x = math.cos(angle), z = math.sin(angle) }
end

local radius = 2.5
local pts, allOn = {}, true
for j = 1, CircleSegments do
    local m = CircleMults[j]
    local sc, on = WorldToScreen(pos + Vector3.new(m.x * radius, -3, m.z * radius))
    if not on or not sc then allOn = false
    else pts[j] = Vector2.new(math.floor(sc.X+0.5), math.floor(sc.Y+0.5)) end
end
if allOn then
    for j = 1, CircleSegments do
        local nextIdx = (j % CircleSegments) + 1
        lines[j].From = pts[j]
        lines[j].To   = pts[nextIdx]
        lines[j].Visible = true
    end
end
-- The -3 Y offset drops the ring to foot level
```

### Gradient Tracer

```lua
local c1, c2 = Config.TracerColor, Config.TracerColor2
local dr, dg, db = c2.R-c1.R, c2.G-c1.G, c2.B-c1.B
for j = 1, segments do
    local t = j / segments
    lines[j].Color = Color3.new(c1.R + dr*t, c1.G + dg*t, c1.B + db*t)
end
```

### Drawing Cache / Cleanup Pattern

```lua
local PlayerDrawings = {}

-- Create on first sight
if not PlayerDrawings[name] then
    PlayerDrawings[name] = {
        Name  = Drawing.new("Text"),
        Lines = {}
    }
end

-- Hide when not needed (don't Remove — reuse next frame)
cache.Name.Visible = false

-- Remove when player leaves
for cachedName, cache in pairs(PlayerDrawings) do
    if not activePlayers[cachedName] then
        cache.Name:Remove()
        for _, line in pairs(cache.Lines) do line:Remove() end
        PlayerDrawings[cachedName] = nil
    end
end
```

---

## Gameplay Patterns

### UI Object Alignment Check

```lua
local function AreUIObjectsAligned(ObjectA, ObjectB)
    local posA, sizeA = ObjectA.AbsolutePosition, ObjectA.AbsoluteSize
    local posB, sizeB = ObjectB.AbsolutePosition, ObjectB.AbsoluteSize
    local centerAX = posA.X + (sizeA.X / 2)
    local centerAY = posA.Y + (sizeA.Y / 2)
    local centerBX = posB.X + (sizeB.X / 2)
    local centerBY = posB.Y + (sizeB.Y / 2)
    local diffX = centerAX - centerBX
    local diffY = centerAY - centerBY
    local distance = math.sqrt(diffX^2 + diffY^2)
    -- AABB overlap check
    local isAligned = (math.abs(diffX) < (sizeA.X + sizeB.X) / 2)
                  and (math.abs(diffY) < (sizeA.Y + sizeB.Y) / 2)
    return isAligned, distance
end
```

> **Note:** Requires `AbsolutePosition` and `AbsoluteSize` to be accessible on the objects — untested in Matcha. These properties exist on Roblox GUI objects but may be nil via the Matcha API.

### ScreenGui Enabled Check via Memory

```lua
local OffsetsJSON = game:HttpGet("https://offsets.ntgetwritewatch.workers.dev/offsets.json")
local Offsets = game:GetService("HttpService"):JSONDecode(OffsetsJSON)

local function IsScreenGuiEnabled(screenGui)
    if not screenGui then return false end
    local status = memory_read("byte", screenGui.Address + Offsets.ScreenGuiEnabled)
    return tonumber(status) ~= 0
end
```

### Color Scan (Brute Force)

Scans memory for valid RGB float triplets — useful for finding color offsets on unknown instances:

```lua
local function BruteForceColor(address, range)
    range = range or 1024
    for offset = 0, range, 4 do
        local r = memory_read("float", address + offset)
        local g = memory_read("float", address + offset + 4)
        local b = memory_read("float", address + offset + 8)
        if type(r)=="number" and type(g)=="number" and type(b)=="number" then
            local valid = r>=0.0001 and r<=1 and g>=0.0001 and g<=1 and b>=0.0001 and b<=1
            local white = r==1 and g==1 and b==1
            if valid and not white then
                print(string.format("COLOR [0x%X] R:%.3f G:%.3f B:%.3f", offset, r, g, b))
            end
        end
    end
end
```

### Text Color via Memory

Text color offset confirmed at `Address + 0xE70`:

```lua
local function GetTextColor(address)
    if not address or address == 0 then return nil end
    local r = memory_read("float", address + 0xE70)
    local g = memory_read("float", address + 0xE70 + 4)
    local b = memory_read("float", address + 0xE70 + 8)
    return Color3.new(r, g, b)
end
```

### Color Comparison with Tolerance

```lua
local function ColorsMatch(a, b, tolerance)
    tolerance = tolerance or 0.1
    if not a or not b then return false end
    return math.abs(a.R-b.R) <= tolerance
       and math.abs(a.G-b.G) <= tolerance
       and math.abs(a.B-b.B) <= tolerance
end
```

### Gravity Control via Memory

```lua
local worldPtr = memory_read("uintptr_t", workspace.Address + 0x3D8)
local function setGravity(gravity)
    memory_write("float", worldPtr + 0x1D0, gravity)
end
setGravity(10)   -- default Roblox gravity is 196.2
setGravity(0)    -- zero gravity
setGravity(196)  -- default
```

> **Note:** `workspace.Address + 0x3D8` is a pointer to the physics world. The gravity float sits at `worldPtr + 0x1D0`. These offsets may be version-specific.

### loadstring Hook — Dump Obfuscated Scripts

```lua
local old_loadstring = loadstring
loadstring = function(str, ...)
    if type(str) == "string" and #str > 0 then
        setclipboard(str)
        notify("dumped to clipboard (" .. #str .. " chars)", "loadstring hook", 4)
    end
    return old_loadstring(str, ...)
end
-- Do NOT hook string.char — crashes Matcha with thousands of prints
```

---

## Drawing-Based Animated UI

A pattern for building fully animated, interactive Drawing overlays without UILib.

### Rounded Rectangle

No native rounded rectangle in Matcha. Simulate with two overlapping Squares and four corner Circles:

```lua
local function layoutRoundedRect(s1, s2, c1, c2, c3, c4, x, y, w, h, r)
    r = math.min(r, math.floor(math.min(w, h) / 2))
    s1.Position = Vector2.new(x+r, y);   s1.Size = Vector2.new(w-r*2, h)
    s2.Position = Vector2.new(x, y+r);   s2.Size = Vector2.new(w, h-r*2)
    c1.Position = Vector2.new(x+r,   y+r);   c1.Radius = r
    c2.Position = Vector2.new(x+w-r, y+r);   c2.Radius = r
    c3.Position = Vector2.new(x+r,   y+h-r); c3.Radius = r
    c4.Position = Vector2.new(x+w-r, y+h-r); c4.Radius = r
end

-- Border lines connect flat edges between corners
bL1.From = Vector2.new(x+r, y);    bL1.To = Vector2.new(x+w-r, y)
bL2.From = Vector2.new(x+r, y+h);  bL2.To = Vector2.new(x+w-r, y+h)
bL3.From = Vector2.new(x, y+r);    bL3.To = Vector2.new(x, y+h-r)
bL4.From = Vector2.new(x+w, y+r);  bL4.To = Vector2.new(x+w, y+h-r)
```

### Scale-In Animation

```lua
local dur, t0 = 0.4, tick()
while tick()-t0 < dur do
    local p  = (tick()-t0)/dur
    local ep = 1-(1-p)^3    -- cubic ease-out
    local cw = math.max(2, math.floor(CW*ep))
    local ch = math.max(2, math.floor(CH*ep))
    layoutRoundedRect(...)
    task.wait(0.016)
end
```

### Slide-In + Fade-In with Stagger

```lua
-- contentItems = list of {obj, bx, by, delay}
local slideOff = 20
while tick()-t0 < totalDur do
    local elapsed = tick() - t0
    for _, ci in ipairs(contentItems) do
        local t = elapsed - (ci.delay or 0)
        if t < 0 then
            ci.obj.Transparency = 0
        elseif t < slideDur then
            local ep = 1-(1-(t/slideDur))^3
            ci.obj.Transparency = ep
            ci.obj.Position = Vector2.new(ci.bx, ci.by + math.floor(slideOff*(1-ep)))
        else
            ci.obj.Transparency = 1
            ci.obj.Position = Vector2.new(ci.bx, ci.by)
        end
    end
    task.wait(0.016)
end
```

### Button Hover Scale

```lua
btn.targetScale = onHover and 1.08 or 1.0
btn.curScale = btn.curScale + (btn.targetScale - btn.curScale) * 0.15
layoutBtn(btn, btn.curScale)
```

### Click Bounce Animation

```lua
-- t goes 0→1 over 0.4s
if     t < 0.25 then sc = lerp(1.08, 0.88, easeOut(t/0.25))
elseif t < 0.55 then sc = lerp(0.88, 1.06, easeOut((t-0.25)/0.3))
elseif t < 0.80 then sc = lerp(1.06, 0.97, easeOut((t-0.55)/0.25))
else                 sc = lerp(0.97, 1.00, easeOut((t-0.80)/0.2))
end
```

### Draggable Card

```lua
local _drg, _dox, _doy = false, 0, 0

if m1 and onCard and not onButton then
    _drg = true; _dox = mx; _doy = my
end

if _drg then
    local dx, dy = mx - _dox, my - _doy
    scx = scx + dx; scy = scy + dy
    _dox = mx; _doy = my
end
```

### Mouse Hit Testing

```lua
local function ins(mx, my, rx, ry, rw, rh)
    return mx >= rx and mx <= rx+rw and my >= ry and my <= ry+rh
end
```

### Drawing Object Pool

```lua
local dObjs = {}
local function mk(typ, props)
    local o = Drawing.new(typ)
    for k, v in pairs(props) do o[k] = v end
    table.insert(dObjs, o)
    return o
end
local function cleanup()
    for _, o in ipairs(dObjs) do pcall(function() o:Remove() end) end
    table.clear(dObjs)
end
```

### Fade-Out on Exit

```lua
local snap = {}
for _, o in ipairs(dObjs) do table.insert(snap, o) end
local t0, dur = tick(), 0.3
while tick()-t0 < dur do
    local ep = (tick()-t0)/dur
    for _, o in ipairs(snap) do pcall(function() o.Transparency = 1-ep end) end
    task.wait(0.016)
end
cleanup()
```

### Font Fallback

```lua
local FNT = Drawing.Fonts.Monospace
pcall(function() FNT = Drawing.Fonts.System end)
local FNTB = FNT
pcall(function() FNTB = Drawing.Fonts.SystemBold end)
```

---

## Utility Patterns

### Position HUD

```lua
local text = Drawing.new("Text")
text.Size     = 16
text.Position = Vector2.new(100, 100)
text.Outline  = true
text.Visible  = true

while true do
    local char = game:GetService("Players").LocalPlayer.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        local pos = char.HumanoidRootPart.Position
        text.Text = string.format("X: %.1f  Y: %.1f  Z: %.1f", pos.X, pos.Y, pos.Z)
    end
    task.wait()
end
```

### GetPing (current)

```lua
-- Simple one-liner
local ping = GetPingValue()   -- returns ms as number
```

---

## Safe Coding Patterns

### Always pcall Remote Instance Reads

```lua
local ok, val = pcall(function() return instance.SomeProperty end)
if ok and val then ... end

-- pcall on IsA (can return weird values in Matcha)
local ok, result = pcall(function() return instance:IsA("BasePart") end)
if ok and result == true then ... end  -- explicit true check
```

> `pcall` returning `true` does not guarantee the value isn't nil in Matcha — always check both: `if ok and value then`.

### Safe Chained FindFirstChild

```lua
local function SafeFind(parent, ...)
    if not parent then return nil end
    for _, name in ipairs({...}) do
        parent = parent:FindFirstChild(name)
        if not parent then return nil end
    end
    return parent
end

local healthBar = SafeFind(LocalPlayer, "PlayerGui", "Main", "Health", "Bar")
```

### Squared Distance (avoid math.sqrt in tight loops)

```lua
local function distSq(a, b)
    local dx = b.X - a.X
    local dy = b.Y - a.Y
    local dz = b.Z - a.Z
    return dx*dx + dy*dy + dz*dz
end

if distSq(posA, posB) < (RANGE * RANGE) then
    -- in range
end
```

### Defer LocalPlayer Reads

```lua
-- WRONG — LocalPlayer can be nil at script start
local LocalPlayer = Players.LocalPlayer  -- at top level

-- CORRECT — fetch inside functions
local function doThing()
    local LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then return end
    ...
end
```

### Use next Instead of ipairs for Non-Contiguous Tables

```lua
for k, v in next, myTable do ... end
```

### Memory Pointer Helpers

```lua
local function readStr(addr)
    if not addr or addr <= 4096 then return nil end
    local ok, v = pcall(memory_read, "string", addr)
    return ok and v or nil
end

local function readPtr(addr)
    if not addr or addr <= 4096 then return nil end
    local ok, v = pcall(memory_read, "uintptr_t", addr)
    return (ok and v and v > 4096) and v or nil
end
```

---

## Performance Tips

### Localize Globals in Tight Loops

```lua
local math_floor  = math.floor
local math_cos    = math.cos
local math_sin    = math.sin
local math_sqrt   = math.sqrt
local math_pi2    = math.pi * 2
local Vector2_new = Vector2.new
local Vector3_new = Vector3.new
local Color3_new  = Color3.new
local Drawing_new = Drawing.new
local os_clock    = os.clock
local task_spawn  = task.spawn
local task_wait   = task.wait
local WTS         = WorldToScreen
local mem_read    = memory_read
```

### Round Screen Positions to Integers

Eliminates sub-pixel blur on Drawing lines/text:

```lua
local function roundVec2(v)
    if not v then return Vector2.new(0, 0) end
    return Vector2.new(math.floor(v.X + 0.5), math.floor(v.Y + 0.5))
end
```

### vector Library Over Vector3 for Computation

See [vector Library](#vector-native-luau-type) section for benchmarks. Use `vector` for inner loops, convert to `Vector3` only when calling `WorldToScreen` or API methods.

---

## Roblox Engine Physics Validation — Memory Write Safety

### How Roblox Server Validation Works

This is **not game-specific anticheat** — it is Roblox's own engine-level physics validation that applies to every game on the platform regardless of whether the developer implemented any anticheat. The server validates **observable behaviour**, not memory values directly. It compares the client's reported position delta per tick against the WalkSpeed the character should have. If displacement is impossible for the given speed, the server kicks with **error code 268** ("Kicked by server" — intentional engine rejection, not a crash or ban).

### What Gets You Kicked

**WalkSpeed writes while moving** — the only confirmed kick trigger.

```lua
-- DANGEROUS — write this then move
memory_write("float", addr + HUM.WalkSpeed, 32)  -- kick if you walk
```

### What Does NOT Get You Kicked

Tested at 2× default values, held for 2+ seconds while standing still, no kick:
- `Health = 200` while `MaxHealth = 100`
- `MaxHealth = 200`
- `JumpPower = 100`
- `JumpHeight = 14.4`
- All 5 fields written simultaneously while **standing still**

### The Persistent Cross-Game Kick

When WalkSpeed is written and you move, the kick (error 268) can corrupt the Roblox client's movement state. Every new server you join will also kick you until you **fully restart the Roblox client**. This is not an account ban — it clears on client restart.

### Safe Memory Write Patterns

```lua
-- Safe: write, stand still, restore before moving
local orig = memory_read("float", addr + HUM.WalkSpeed)
memory_write("float", addr + HUM.WalkSpeed, 32)
-- do something that doesn't require movement
memory_write("float", addr + HUM.WalkSpeed, orig)

-- Safe: CFrame teleport instead of WalkSpeed for repositioning
hrp.CFrame = hrp.CFrame + Vector3.new(0, 0, -50)  -- not validated the same way

-- Safe: Health, MaxHealth, JumpPower, JumpHeight writes
memory_write("float", addr + HUM.Health,    200)
memory_write("float", addr + HUM.JumpPower, 100)
```

### Offset Safety Table

| Offset | Field | Write Safety |
|--------|-------|-------------|
| 404 | Health | ✅ Safe — server doesn't validate HP bounds |
| 436 | MaxHealth | ✅ Safe |
| 428 | JumpHeight | ✅ Safe |
| 432 | JumpPower | ✅ Safe |
| 420 | AutoRotate (bool-float) | ⚠ Unknown — no kick in isolation, but avoid |
| 440 | MaxSlopeAngle | ⚠ Unknown |
| 468 | WalkSpeed | ❌ DANGEROUS if moving — causes error 268 + persistent cross-game kick |

**Offset 420 — AutoRotate:** Holds `1.0` (enabled) or `0.0` (disabled) as a float. Writing `0` disables automatic character rotation. Does not cause kicks in isolation but produces visible behaviour change. Treat as unknown risk — avoid in production scripts.

---


## General Tips

- Wrap ALL property reads on remote instances in `pcall` — Matcha can throw instead of returning nil
- `pcall` returning `true` does not mean value isn't nil — always check `if ok and value then`
- `setclipboard()` is useful for extracting data during debugging
- `Drawing.new("Text")` is confirmed working — earlier bug reports were incorrect
- `task.wait()` stacking causes timing issues — keep waits simple
- `string.format` works normally
- `os.clock()` works for timing; `tick()` is session uptime (not Unix time); `os.time()` for timestamps
- `math` library works fully
- `continue` keyword works inside loops
- `goto` is not supported — use nested ifs instead
- Scripts crash with "attempt to index nil with 'Name'" when `LocalPlayer` is nil at script start — always defer reads into functions
- `Color3.fromRGB` takes 0–255, `Color3.new` takes 0–1, `BrickColor.Color` returns 0–1 — don't mix them
- `IsA()` can return unexpected values — always compare with `== true` explicitly
- Use `typeof(v) == "Vector3"` instead of `type(v) == "userdata"` for cleaner type checking
- `isrbxactive()` can gate input simulation — only send keys when window is focused
- `bit32.band(addr, 0xFFFFFFFF)` clamps a number to 32-bit unsigned before memory writes
- `buffer` is the cleanest way to build multi-field memory write payloads
- `warn()` output is visually distinct from `print()` in the Matcha console — use it for errors/alerts
- `gcinfo()` returns KB used — call before/after large operations to track memory pressure
- String metatable extensions persist for the entire session — add utility methods once at the top
- No `RunService:IsClient()` / `IsServer()` — these crash. Events only.
- No `Instance.new` — cannot create new Roblox Instances from Matcha
- `Enum` is severely stripped — only `Enum.KeyCode` is available
