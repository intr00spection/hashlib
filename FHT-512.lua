--[[
A custom hashing algorithm that uses a randomly generated string of numbers to determine the hash of a given input string.
Normally, the string of numbers is split into 10 characters, and each character is used to determine the specific operation.
the string of numbers looks like this:
4803685771
3750575706
2543449605
0369156481
where each number corresponds to a specific operation in the fixed opcode dictionary. 
]]
local rounds = 2
local rotAbsorb = 2
local rotAvalanche = 2

local opcodes = {
	[0] = function(val, prev, curr) -- ADD
		return bit32.band(val + prev + curr, 0xFFFFFFFF)
	end,

	[1] = function(val, prev, curr) -- SUB + XOR
		return bit32.band(bit32.bxor(val - prev, curr), 0xFFFFFFFF)
	end,

	[2] = function(val, prev, curr) -- XOR x2
		return bit32.bxor(bit32.bxor(val, prev), curr)
	end,

	[3] = function(val, prev, curr) -- OR-XOR
		return bit32.bxor(bit32.bor(val, prev), curr)
	end,

	[4] = function(val, prev, curr) -- AND-NOT
		return bit32.bxor(bit32.band(val, prev), bit32.band(bit32.bnot(curr), 0xFFFFFFFF))
	end,

	[5] = function(val, prev, curr) -- left rotate, input-driven
		return bit32.lrotate(bit32.bxor(val, curr), prev % 32)
	end,

	[6] = function(val, prev, curr) -- right rotate, input-driven
		return bit32.rrotate(bit32.bxor(val, prev), curr % 32)
	end,

	[7] = function(val, prev, curr) -- ROL5
		return bit32.band(bit32.lrotate(val, 5) + bit32.bxor(prev, curr), 0xFFFFFFFF)
	end,

	[8] = function(val, prev, curr) -- ROR5
		return bit32.band(bit32.bxor(bit32.rrotate(val, 5), val + curr), 0xFFFFFFFF)
	end,

	[9] = function(val, prev, curr) -- MUL
		return bit32.band((val * bit32.bor(prev, 1)) + curr, 0xFFFFFFFF)
	end,
}

local function digest(operations: string, input: string, stateKey: string): string
    assert(#stateKey > 0, "stateKey must be non-empty")
	assert(string.match(operations, "^%d+$"), "operations must be a non-empty string of digits 0-9")
    
    local function parseOperations() -- Parser, so we can use our own opcode operations
        local parsed = {}
        for i = 1, #operations do
           parsed[i] = tonumber(string.sub(operations, i, i))
        end
        return parsed
    end

	local function padData()
		local len = #input
		local bytes = table.create(len + 16)

		for i = 1, len do
			bytes[i] = string.byte(input, i)
		end
		-- delimiter marks end of real data
		table.insert(bytes, 0x80)
        
		for i = 0, 3 do
			table.insert(bytes, bit32.band(bit32.rshift(len, i * 8), 0xFF))
		end
		while (#bytes % 16) ~= 0 do
			table.insert(bytes, 0x00)
		end
		return bytes
	end
    
    local function process(parsed, inBytes, state)
		local opidx = 1
		for i, byte in next, inBytes do
			local opcode = parsed[opidx]
			opidx = (opidx % #parsed) + 1

			local stateidx = ((i - 1) % #state) + 1
			local previdx = ((stateidx - 2) % #state) + 1
			local nextidx = (stateidx % #state) + 1

			local mixed = opcodes[opcode](byte, state[previdx], state[stateidx])

			state[stateidx] = mixed
			state[nextidx] = bit32.band(state[nextidx] + bit32.lrotate(mixed, rotAbsorb), 0xFFFFFFFF)
		end

		-- "Avalanche", bleeds mutations through the entire state instead of the local state
		for _ = 1, rounds do
			for stateidx = 1, #state do
				local opcode = parsed[opidx]
				opidx = (opidx % #parsed) + 1
				local previdx = ((stateidx - 2) % #state) + 1
				local nextidx = (stateidx % #state) + 1

				local mixed = opcodes[opcode](state[stateidx], state[previdx], state[nextidx])
				state[stateidx] = mixed
				state[nextidx] = bit32.band(state[nextidx] + bit32.lrotate(mixed, rotAvalanche), 0xFFFFFFFF)
			end
		end
	end

    local function formatHex(state) -- Formatting
        local parts = table.create(#state)
        for i, word in next, state do
            parts[i] = string.format("%08x", word)
        end
        return table.concat(parts)
    end

    local function foldKey(key: string, state)
        for i = 1, #key do
            local byte = string.byte(key, i)

			local stateidx = ((i - 1) % #state) + 1
			local previdx = ((stateidx - 2) % #state) + 1
			local nextidx = (stateidx % #state) + 1

			state[stateidx] = bit32.band(bit32.bxor(state[stateidx], byte), 0xFFFFFFFF)
			state[stateidx] = bit32.lrotate(state[stateidx], (byte + i) % 32)
			state[nextidx] = bit32.band(state[nextidx] + bit32.lrotate(state[stateidx], 7), 0xFFFFFFFF)
        end
    end
    
	local function generateIV(key: string)
		local defaults = {
			0x12345678, 0x9ABCDEF0, 0x13579BDF, 0x2468ACE0,
			0xA1B2C3D4, 0xE5F60718, 0x293A4B5C, 0x6D7E8F90,
		}
		local generated = table.create(8)
		for i = 1, 8 do
			generated[i] = defaults[i]
		end
		foldKey(key, generated)
		return generated
	end
    
    local currentoperations = parseOperations()
    local padded = padData()

    local internal = generateIV(stateKey)

    process(currentoperations, padded, internal)

    foldKey(stateKey, internal)
    
    return formatHex(internal)
end


local input = "Input your desired string here.."
local numbers = "type a random mix of letters, 1-9 here; example: 85346753426705437809254732654"
local IV = "Make this any mix of letters, preferrably over 32 characters."
print(digest(numbers, input, IV))
