-- https://github.com/ImagicTheCat/lua-algen
-- MIT license (see LICENSE or src/algen.lua)
--[[
MIT License

Copyright (c) 2021 ImagicTheCat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local ffi = require("ffi")
local bit = require("bit")
local LuaJIT_2_1 = jit.version:find("2%.1%.") ~= nil

local band, bor, bxor = bit.band, bit.bor, bit.bxor
local band64, bor64, bxor64, lshift64, rshift64 = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
-- Implement 64bit bitwise operations for LuaJIT 2.0.
if not LuaJIT_2_1 then
  local function split(a) return tonumber(a / 2^32), tonumber(a % 2^32) end
  local function merge(h, l) return h*2^32ULL + l end
  local function op(f, a, b)
    local ah, al = split(a)
    local bh, bl = split(b)
    local h, l = f(ah, bh), f(al, bl)
    return merge(h % 2^32ULL, l % 2^32ULL) -- convert h and l to 32bit unsigned
  end
  band64 = function(a, b) return op(band, a, b) end
  bor64 = function(a, b) return op(bor, a, b) end
  bxor64 = function(a, b) return op(bxor, a, b) end
  lshift64 = function(a, n) return a * 2ULL^n end
  rshift64 = function(a, n) return a / 2ULL^n end
end

-- Module

local algen = {}

local U64double = ffi.typeof("union{ uint64_t u64; double d; }")

-- Re-implementation of LuaJIT's random number generator.
-- Original implementation comments are quoted, see LuaJIT's lj_prng.c and
-- lib_math.c (license below).
--[[
LuaJIT -- a Just-In-Time Compiler for Lua. https://luajit.org/

Copyright (C) 2005-2021 Mike Pall. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

[ MIT license: https://www.opensource.org/licenses/mit-license.php ]
]]

--[[
"This implements a Tausworthe PRNG with period 2^223. Based on:
  Tables of maximally-equidistributed combined LFSR generators,
  Pierre L'Ecuyer, 1991, table 3, 1st entry.
Full-period ME-CF generator with L=64, J=4, k=223, N1=49."
]]

ffi.cdef[[ struct algen_generator_t{ uint64_t u[4]; } ]]

local generator = {}
local generator_t = ffi.typeof("struct algen_generator_t")

-- "Update generator i and compute a running xor of all states."
local function TW223_gen(self, r, i, k, q, s)
  local z = self.u[i]
  z = bxor64(
    rshift64(bxor64(lshift64(z, q), z), k-s),
    lshift64(band64(z, lshift64(0xffffffffffffffffULL, 64-k)), s)
  )
  r = bxor64(r, z)
  self.u[i] = z
  return r
end

local function generator_step(self)
  local r = 0ULL
  r = TW223_gen(self, r, 0, 63, 31, 18)
  r = TW223_gen(self, r, 1, 58, 19, 28)
  r = TW223_gen(self, r, 2, 55, 24,  7)
  r = TW223_gen(self, r, 3, 47, 21,  8)
  return r
end

-- 1 << 64-k[i] constants
local K_SEED = {0x2, 0x40, 0x200, 0x20000}
local u = U64double() -- optimization: avoid allocation

-- Create a new generator.
-- Implements the same random function as LuaJIT's math.random(), a Tausworthe
-- PRNG with period 2^223 (see LuaJIT's documentation). It produces the same sequences.
--
-- seed: (optional) number (default: 0)
function algen.generator(seed)
  seed = seed or 0
  if type(seed) ~= "number" then error("seed must be a number") end
  local generator = ffi.new(generator_t)
  -- seed the states
  for i=1,4 do
    seed = seed * 3.14159265358979323846 + 2.7182818284590452354
    u.d = seed
    -- "Ensure k[i] MSB of u[i] are non-zero."
    if u.u64 < K_SEED[i] then u.u64 = u.u64 + K_SEED[i] end
    generator.u[i-1] = u.u64
  end
  for i=1,10 do generator_step(generator) end
  return generator
end

-- Generate uint64_t cdata (ULL) random number (generator step).
generator.randomU64 = generator_step

-- Generate random number (generator step).
-- Same API as math.random([m [, n]]).
-- Alias: generator(...)
function generator:random(m, n)
  local r = generator_step(self)
  -- "Returns a double bit pattern in the range 1.0 <= d < 2.0."
  u.u64 = bor64(band64(r, 0x000fffffffffffffULL), 0x3ff0000000000000ULL)
  local d = u.d-1 -- d is a double in range [0, 1]
  if m then
    if n then
      return math.floor(d*(n-m+1.0))+m -- return int in range [m, n]
    else return math.floor(d*m)+1 end -- return int in range [1, m]
  end
  return d
end

-- Save the state of the generator as a portable platform-independent string.
function generator:save()
  local t = {}
  for i=0,3 do
    local s = ffi.string(self.u+i, 8)
    if not ffi.abi("le") then s = s:reverse() end
    t[i+1] = s
  end
  return table.concat(t)
end

-- Load a previously saved state into the generator.
-- state: string
function generator:load(state)
  if #state ~= 4*8 then error("invalid state data") end
  for i=0,3 do
    local s = state:sub(1+i*8, 8+i*8)
    if not ffi.abi("le") then s = s:reverse() end
    ffi.copy(self.u+i, s, 8)
  end
end

ffi.metatype(generator_t, {__index = generator, __call = generator.random})

return algen 
