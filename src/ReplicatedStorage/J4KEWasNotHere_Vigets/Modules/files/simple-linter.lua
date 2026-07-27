--!strict

--[[
	Minimal Luau re-indenter for generated source. Discards each line's
	existing leading whitespace and recomputes it from bracket/keyword
	nesting depth. Not a full parser — good enough for generated code
	(tables, function wrappers, simple calls).
]]

local INDENT = "\t"

local WORD_KEYWORDS = {
	"function",
	"if",
	"elseif",
	"else",
	"for",
	"while",
	"do",
	"repeat",
	"until",
	"end",
	"then",
}

-- Replaces string/comment bodies with spaces (keeping newlines) so bracket
-- and keyword scanning below ignores anything inside them.
local function maskStringsAndComments(source: string): string
	local out = table.create(#source)
	local n = #source
	local i = 1

	local function fill(from: number, to: number)
		for k = from, to do
			out[k] = source:sub(k, k) == "\n" and "\n" or " "
		end
	end

	while i <= n do
		local c, c2 = source:sub(i, i), source:sub(i + 1, i + 1)

		if c == "-" and c2 == "-" then
			local j = i + 2
			local eq = 0
			if source:sub(j, j) == "[" then
				local k = j + 1
				while source:sub(k, k) == "=" do
					eq += 1
					k += 1
				end
				if source:sub(k, k) == "[" then
					local _, closeEnd = source:find("%]" .. string.rep("=", eq) .. "%]", k + 1)
					local finish = closeEnd or n
					fill(i, finish)
					i = finish + 1
					continue
				end
			end
			local lineEnd = source:find("\n", i, true)
			local finish = (lineEnd and lineEnd - 1) or n
			fill(i, finish)
			i = finish + 1
			continue
		end

		if c == "[" and (c2 == "[" or c2 == "=") then
			local k = i + 1
			local eq = 0
			while source:sub(k, k) == "=" do
				eq += 1
				k += 1
			end
			if source:sub(k, k) == "[" then
				local _, closeEnd = source:find("%]" .. string.rep("=", eq) .. "%]", k + 1)
				local finish = closeEnd or n
				fill(i, finish)
				i = finish + 1
				continue
			end
		end

		if c == '"' or c == "'" then
			local quote = c
			local j = i + 1
			while j <= n do
				local cj = source:sub(j, j)
				if cj == "\\" then
					j += 2
				elseif cj == quote then
					j += 1
					break
				elseif cj == "\n" then
					break
				else
					j += 1
				end
			end
			fill(i, j - 1)
			i = j
			continue
		end

		out[i] = c
		i += 1
	end

	return table.concat(out)
end

local function scanTokens(maskedLine: string): { string }
	local tokens, i, n = {}, 1, #maskedLine
	while i <= n do
		local c = maskedLine:sub(i, i)
		if c == "{" or c == "}" or c == "(" or c == ")" or c == "[" or c == "]" then
			table.insert(tokens, c)
			i += 1
		elseif c:match("[%a_]") then
			local j = i
			while j <= n and maskedLine:sub(j, j):match("[%w_]") do
				j += 1
			end
			local word = maskedLine:sub(i, j - 1)
			for _, kw in WORD_KEYWORDS do
				if word == kw then
					table.insert(tokens, word)
					break
				end
			end
			i = j
		else
			i += 1
		end
	end
	return tokens
end

local function splitLines(s: string): { string }
	local lines = {}
	for line in (s .. "\n"):gmatch("(.-)\n") do
		table.insert(lines, line)
	end
	return lines
end

local function indent(code: string): string
	local rawLines = splitLines(code)
	local maskedLines = splitLines(maskStringsAndComments(code))

	local out = table.create(#rawLines)
	local depth = 0
	local blockStack: { string } = {}

	for idx = 1, #rawLines do
		local trimmed = rawLines[idx]:match("^%s*(.-)%s*$")
		local maskedTrimmed = maskedLines[idx]:match("^%s*(.-)%s*$") or ""

		if trimmed == "" then
			table.insert(out, "")
			continue
		end

		local tokens = scanTokens(maskedTrimmed)

		local leadingCloses = 0
		for _, tok in tokens do
			if tok == "}" or tok == ")" or tok == "]" or tok == "end" or tok == "until" then
				leadingCloses += 1
			else
				break
			end
		end

		local displayDepth = math.max(depth - leadingCloses, 0)
		if maskedTrimmed:match("^else%f[%A]") or maskedTrimmed:match("^elseif%f[%A]") then
			displayDepth = math.max(depth - 1, 0)
		end

		table.insert(out, string.rep(INDENT, displayDepth) .. trimmed)

		for _, tok in tokens do
			if tok == "{" or tok == "(" or tok == "[" then
				depth += 1
			elseif tok == "}" or tok == ")" or tok == "]" then
				depth = math.max(depth - 1, 0)
			elseif tok == "do" then
				if blockStack[#blockStack] == "for-while-pending" then
					blockStack[#blockStack] = "do"
				else
					depth += 1
					table.insert(blockStack, "do")
				end
			elseif tok == "for" or tok == "while" then
				table.insert(blockStack, "for-while-pending")
				depth += 1
			elseif tok == "function" or tok == "if" or tok == "repeat" then
				table.insert(blockStack, tok)
				depth += 1
			elseif tok == "end" or tok == "until" then
				depth = math.max(depth - 1, 0)
				table.remove(blockStack)
			end
		end
	end

	return table.concat(out, "\n")
end

return function(code: string): string
	return indent(code)
end
