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

type Token = { value: string, pos: number, hug: boolean? }

local function scanTokens(maskedLine: string): { Token }
	local tokens: { Token } = {}
	local i, n = 1, #maskedLine
	while i <= n do
		local c = maskedLine:sub(i, i)
		if c == "{" or c == "}" or c == "(" or c == ")" or c == "[" or c == "]" then
			table.insert(tokens, { value = c, pos = i })
			i += 1
		elseif c:match("[%a_]") then
			local j = i
			while j <= n and maskedLine:sub(j, j):match("[%w_]") do
				j += 1
			end
			local word = maskedLine:sub(i, j - 1)
			for _, kw in WORD_KEYWORDS do
				if word == kw then
					table.insert(tokens, { value = word, pos = i })
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

local function isOpenBracket(v: string): boolean
	return v == "{" or v == "(" or v == "["
end

local function isCloseBracket(v: string): boolean
	return v == "}" or v == ")" or v == "]"
end

local function isCloser(v: string): boolean
	return isCloseBracket(v) or v == "end" or v == "until"
end

local function markHugs(tokens: { Token }, maskedLine: string)
	for idx = 1, #tokens - 1 do
		local a, b = tokens[idx], tokens[idx + 1]
		if a.value == "(" and b.value == "{" then
			local between = maskedLine:sub(a.pos + 1, b.pos - 1)
			if between:match("^%s*$") then
				a.hug = true
			end
		end
	end
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

	local bracketStack: { boolean } = {}

	local function popBracket(stack: { boolean }): boolean
		if #stack == 0 then
			return true
		end
		local contributing = stack[#stack]
		table.remove(stack)
		return contributing
	end

	for idx = 1, #rawLines do
		local trimmed = rawLines[idx]:match("^%s*(.-)%s*$")
		local maskedTrimmed = maskedLines[idx]:match("^%s*(.-)%s*$") or ""

		if trimmed == "" then
			table.insert(out, "")
			continue
		end

		local tokens = scanTokens(maskedTrimmed)
		markHugs(tokens, maskedTrimmed)

		local depthAtLineStart = depth

		local shadowStack = table.clone(bracketStack)
		local shadowDepth = depth
		for _, tok in tokens do
			if not isCloser(tok.value) then
				break
			end
			if isCloseBracket(tok.value) then
				if popBracket(shadowStack) then
					shadowDepth = math.max(shadowDepth - 1, 0)
				end
			else -- "end" or "until"
				shadowDepth = math.max(shadowDepth - 1, 0)
			end
		end

		local displayDepth = shadowDepth
		if maskedTrimmed:match("^else%f[%A]") or maskedTrimmed:match("^elseif%f[%A]") then
			displayDepth = math.max(depthAtLineStart - 1, 0)
		end

		table.insert(out, string.rep(INDENT, displayDepth) .. trimmed)

		-- Real pass: mutate depth/bracketStack/blockStack for every token.
		for _, tok in tokens do
			local v = tok.value
			if isOpenBracket(v) then
				local contributing = not tok.hug
				table.insert(bracketStack, contributing)
				if contributing then
					depth += 1
				end
			elseif isCloseBracket(v) then
				if popBracket(bracketStack) then
					depth = math.max(depth - 1, 0)
				end
			elseif v == "do" then
				if blockStack[#blockStack] == "for-while-pending" then
					blockStack[#blockStack] = "do"
				else
					depth += 1
					table.insert(blockStack, "do")
				end
			elseif v == "for" or v == "while" then
				table.insert(blockStack, "for-while-pending")
				depth += 1
			elseif v == "function" or v == "if" or v == "repeat" then
				table.insert(blockStack, v)
				depth += 1
			elseif v == "end" or v == "until" then
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
