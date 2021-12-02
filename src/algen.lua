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

local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
local LuaJIT_2_1 = jit.version:find("2%.1%.") ~= nil

local algen = {}

local U64double = ffi.typeof("union{ uint64_t u64; double d; }")

-- generator

ffi.cdef[[
struct algen_generator_t{
  uint64_t u[4];
};
]]

local generator = {}
local generator_t = ffi.typeof("struct algen_generator_t")

local function TW223_gen(self, r, i, k, q, s)
  local z = self.u[i]
  z = bxor(
    rshift(bxor(lshift(z, q), z), k-s),
    lshift(band(z, lshift(0xffffffffffffffffULL, 64-k)), s)
  )
  r = bxor(r, z)
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

function algen.generator(seed)
  seed = seed or 0
  local generator = ffi.new(generator_t)
  -- seed the states
  local u = U64double()
  for i=1,4 do
    seed = seed * 3.14159265358979323846 + 2.7182818284590452354
    u.d = seed
    if u.u64 < K_SEED[i] then u.u64 = u.u64 + K_SEED[i] end
    generator.u[i-1] = u.u64
  end
  for i=1,10 do generator_step(generator) end
  return generator
end

function generator:random(m, n)
  local r = generator_step(self)
  local u = U64double()
  u.u64 = bor(band(r, 0x000fffffffffffffULL), 0x3ff0000000000000ULL)
  local d = u.d-1
  return d
end

function generator:save()
end

function generator:load()
end

ffi.metatype(generator_t, {__index = generator, __call = generator.random})

return algen 
