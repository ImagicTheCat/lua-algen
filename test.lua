#!/usr/bin/env luajit
-- or Lua 5.1

-- config
local envs = {"luajit", "luajit-2.1.0-beta3"}
local tests = {
  "examples/tests.lua"
}
-- test
local errors = 0
for _, env in ipairs(envs) do
  for _, test in ipairs(tests) do
    local status = os.execute(env.." "..test)
    if status ~= 0 then print(env, test, "FAILED"); errors = errors+1 end
  end
end
if errors > 0 then error(errors.." error(s)") end
