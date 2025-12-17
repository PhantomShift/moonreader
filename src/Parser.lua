local StringUtils = require("./StringUtils")
local IterTools = require("./IterTools")
local FunctionParser = require("./FunctionParser")
local Parser = {}

type CommentMetadata = {
	long : {
		indent: string,
		equalLength: number,
	}?,
	dashed : {}?,
}

local LONG_COMMENT_PATTERN = "()(--%[=%[[\n\r].-%]=%])()"
local DASHED_COMMENT_PATTERN = "%-%-%-[^\n\r]*\n?\r?"
local LINE_CAPTURE = "[^\n\r]+"

local function GetLongCommentMeta(s: string) : CommentMetadata
	local metadata = {}

	local iter = StringUtils.IterLines(s) :: () -> string
	local commentStart = iter():match("--%[=%[") :: string
	metadata.equalLength = (commentStart:match("=+") or ""):len()
	local line
	repeat
		line = iter()
	until not (line:len() == 0 or line:match("^%s+$"))
	metadata.indent = line:match("^%s+") or ""

	return { long = metadata }
end

local Tags = {
	-- Doc comments
	class = "@class (%w+)",
	within = "@within (%w+)",
	prop = "@prop ([%w_]+) ([^\n\r]+)",
	type = "@type (%w+) ([^\n\r]+)",
	["function"] = "@function ([%w_]+)",
	method = "@method ([%w_]+)",

	-- Interface stuff
	interface = "@interface (%w+)",
	field = "@field ([^\n\r]*)",
	["."] = "%s*%.(%S[^\n\r]*)", -- interface shorthand

	-- Tag tag
	tag = "@tag (%w+)",

	-- Function tags
	yields = "@yields",
	param = "@param ([^\n\r]*)",
	["return"] = "@return ([^\n\r]+)",
	error = "@error ([^\n\r]+)",

	-- Usage tags
	unreleased = "@unreleased",
	since = "@since ([^\n\r]+)",
	deprecated = "@deprecated ([^\n\r]+)",

	-- Realm tags
	server = "@server",
	client = "@client",
	plugin = "@plugin",

	-- Visibility
	private = "@private",
	ignore = "@ignore",-- TODO: automatically skip processing of classes and other comments tagged `ignore`

	-- Property tags
	readonly = "@readonly",

	-- Class tags
	__index = "@__index (%w+)", -- TODO: respect index tag when detecting methods

	--TODO: Remaining tag "@external" (needs design to be useful)
}

local REQUIRED_TAGS = { class = true, within = true }
local REPEATABLE_TAGS = { param = true, tag = true, ["return"] = true, field = true, ["."] = true, error = true }
local MARKER_TAGS = {
	yields = true,
	ignore = true,

	-- usage
	unreleased = true,

	-- visibility
	private = true,

	-- realm
	client = true,
	server = true,
	plugin = true,

	-- property
	readonly = true
}
local function __name_type_comment_parse(s: string)
	local front, comment = StringUtils.SplitOnce(s, " -- ")
	local name, par_type = StringUtils.SplitOnce(front, " ")
	return table.pack(name, par_type or "", comment)
end
local function __type_opt_desc_parse(s: string)
	return table.pack(StringUtils.SplitOnce(s, " -- "))
end
local COMPLEX_TAGS = {
	param = __name_type_comment_parse,
	field = __name_type_comment_parse,
	["."] = __name_type_comment_parse,
	["return"] = __type_opt_desc_parse,
	error = __type_opt_desc_parse,
	deprecated = __type_opt_desc_parse,
}

export type ParsedComment = {
	__source: string | EditableScript,
	__start: number,
	__end: number,
	class: string,
	within: string,
	prop: {string},
	type: {string},
	interface: string,
	["function"]: string,
	method: string,

	tag: {[string]: {string}},

	yields: boolean,
	param: {{name: string, luaType: string?, description: string?}},
	["return"]: {{luaType: string, description: string?}},
	error: {{luaType: string, description: string?}},

	-- Usage tags
	unreleased: boolean,
	since: string,
	deprecated: {string},

	server: boolean,
	client: boolean,
	plugin: boolean,

	private: boolean,
	ignore: boolean,

	readonly: boolean,

	__index: string,

	description: string,
	__commentType: "Long" | "Dashed",
	__typeParams: {string}?,
}

local NewlineInducers = {
	["%*"] = true,
	["%-"] = true,
	[":::"] = true,
	["#"] = true
}

function Parser.ParseCommentGroup(source: string, start: number, finish: number, commentType: "Long" | "Dashed") : ParsedComment
	local result = {
		__source = source,
		__commentType = commentType,
		__start = start,
		__end = finish
	}
	local comment = source:sub(start, finish)

	local params = {}
	local returns = {}
	local errors = {}

	for tag, pattern in pairs(Tags) do
		local g = comment:gmatch(pattern)
		local info = table.pack(g())
		while info do
			if #info > 0 then
				if COMPLEX_TAGS[tag] then
					info = COMPLEX_TAGS[tag](info[1])
				end

				if REPEATABLE_TAGS[tag] then
					if tag == "." then tag = "field" end

					if result[tag] == nil then result[tag] = {} end
					if tag == "return" then
						table.insert(returns, { luaType = info[1], description = info[2] })
					elseif tag == "error" then
						table.insert(errors, { luaType = info[1], description = info[2] })
					elseif tag == "param" then
						table.insert(params, { name = info[1], luaType = info[2], description = info[3] })
					else
						result[tag][info[1]] = info
					end
				elseif MARKER_TAGS[tag] then
					result[tag] = true
				else
					result[tag] = if info.n == 1 then info[1] else info
				end
			else
				break
			end
			info = table.pack(g())
		end
	end

	result.param = params
	result["return"] = returns
	result.error = errors

	-- Overall entry description
	if commentType == "Long" then
		local meta = GetLongCommentMeta(comment).long
		local indentation = meta.indent
		local equalLength = meta.equalLength
		local commentCloser = `]{("="):rep(equalLength)}]%s*$`
		local prevEmpty = false
		local inCodeBlock = false
		local inNonCodeBlock = false
		result.description = StringUtils.IterLines(comment)
		:filterMap(function(line: string)
			if line:match(commentCloser) then
				return nil
			end
			if not inNonCodeBlock and line:match("^%s+:::") then
				inNonCodeBlock = true
				return line:gsub(`^{indentation}`, "\n") .. "\n"
			end
			if inNonCodeBlock and line:match("^%s+:::") then
				inNonCodeBlock = false
				return line:gsub(`^{indentation}`, "\n\n")
			end
			if line:match("^%s+```") then
				inCodeBlock = not inCodeBlock
				return line:gsub(`^{indentation}`, "\n")
			end
			if inCodeBlock then
				return line:gsub(`^{indentation}`, "\n")
			end
			if line == "" or line:match("^%s+$") and not prevEmpty then
				if prevEmpty then
					return nil
				end
				prevEmpty = true
				return "\n"
			end
			-- if line == "" and not prevEmpty then prevEmpty = true return line end
			if line:match("^%s+") and not line:match("^%s+@") and not line:match("^%s+%.%S") then
				prevEmpty = false
				for pattern in NewlineInducers do
					if line:match(`^%s+{pattern}`) then
						return line:gsub(`^{indentation}`, "\n")
					end
				end
				return line:gsub(`^{indentation}`, "") .. " "
			end
			return nil
		end)
		:concat("")
		:gsub("(%s+)$", "")
	elseif commentType == "Dashed" then
		local first = comment:match("^(.-)[\n\r]")
		local indentation = first:match("^%s*%-+%s*")
		local idents = indentation:len()
		local inCodeBlock = false
		local prevEmpty = false
		result.description = StringUtils.IterLines(comment)
			:filterMap(function(line)
				local text = line:sub(idents + 1)
				if not text:match("^%s*@") and not text:match("^%s*%.%S") then
					if text:match("^```") then
						inCodeBlock = not inCodeBlock
						return `{text}\n`
					end
					if inCodeBlock then
						-- not entirely sure what's causing these to exist?
						if text == "" or text == " " then
							return nil
						end
						return `{text}\n`
					end
					
					if text == "" or text:match("^%s+$") then
						if prevEmpty then
							return nil
						end
						prevEmpty = true
						return "\n"
					end

					for pattern in NewlineInducers do
						if text:match(`^{pattern}`) then
							return `\n{text}\n`
						end
					end
					return `{text} `
				end
				return nil
			end)
			:concat()
			-- :gsub("\n\n", "\n")
	end
	return result
end

--- Returns true if `comment` was modified
function Parser.ApplyFunctionInfo(comment: ParsedComment, info: FunctionParser.FunctionSignature, classIndex: {[string]: string}) : boolean
	-- TODO: Decide what to do with functions that take self as the first argument (i.e. function Class.method(self) end)
	local within, funcName, path, lastSep: string
	local root, back = StringUtils.SplitOnce(info.name, ".")
	lastSep = "."
	if not back then
		root, back = StringUtils.SplitOnce(info.name, ":")
		lastSep = ":"
	end

	if classIndex[root] == nil then
		if comment.within == nil then
			return false
		else
			within = comment.within
		end
	else
		within = root
	end
	if not back then return false end
	local tmpLastSep = back:match(".+([%.:]).-$")
	if tmpLastSep then
		path, funcName = back:match(`(.+)%{tmpLastSep}(.+)$`)
		lastSep = tmpLastSep
	else
		funcName = back
		path = ""
	end

	-- Ignore methods that are not directly attached to the class or attached to its prototype (@__index tag)
	if path ~= "" and path ~= classIndex[within] then return false end
	if not comment.within then
		comment.within = within
	end

	if #info.params > 0 and comment.param == nil then
		comment.param = {}
	end
	for i, param in info.params do
		if comment.param[i] == nil then
			comment.param[i] = param
		else
			comment.param[i].name = comment.param[i].name or param.name
			local t = comment.param[i].luaType
			comment.param[i].luaType = if t and t ~= "" then t else param.luaType
		end
	end
	if comment["return"] == nil then
		comment["return"] = {}
	end
	for i, retType in info.returns do
		if comment["return"][i] == nil then
			comment["return"][i] = { luaType = retType }
		else
			comment["return"][i].luaType = comment["return"][i].luaType or retType
		end
	end

	if comment["function"] == nil or comment.method == nil then
		if lastSep == "." then
			comment["function"] = funcName
		else
			comment.method = funcName
		end
	end

	if #info.genericTypeParams > 0 then
		comment.__typeParams = info.genericTypeParams
	end
	return true
end

function Parser.InferFunctionInformation(parsedComment: ParsedComment, classIndex: {[string]: string})
	if parsedComment.prop or parsedComment.interface or parsedComment["type"] then return end
	local init: number = parsedComment.__end + 1
	-- Only infer if function directly follows the comment
	if (parsedComment.__source :: string):sub(init):match("^[ \t]*\n?[ \t]*function%s") == nil then
		return
	end

	local sigInfo = FunctionParser.ParseSignature(parsedComment.__source :: string, init)
	if sigInfo then
		Parser.ApplyFunctionInfo(parsedComment, sigInfo, classIndex)
	else
		warn("[moonreader] Function parser could not detect function despite being matched?")
		print("[moonreader]", (parsedComment.__source :: string):sub(init, init + 64))
	end
end

function Parser.ReadSource(src: string) : {ParsedComment}
	local results = {}
	for start, _match, finish in src:gmatch(LONG_COMMENT_PATTERN) do
		table.insert(results, Parser.ParseCommentGroup(src, start, finish, "Long"))
	end
	for _match, front, back in StringUtils.GMatchRepeated(src, DASHED_COMMENT_PATTERN, nil, true) do
		table.insert(results, Parser.ParseCommentGroup(src, front, back, "Dashed"))
	end

	-- Secondary pass on parsed comments, infer additional function information for annotated functions
	local classIndex = {}
	for _, result in results do
		if result.class ~= nil then
			classIndex[result.class] = result.__index or "__index"
		end
	end
	for _, result in pairs(results) do
		Parser.InferFunctionInformation(result, classIndex)
	end

	-- Full second pass - detect additional functions/methods that are not annotated
	local functionCache = {}
	for _, result in results do
		local funcName = result.method or result["function"]
		if funcName then
			local cacheName = `{result.within}/{funcName}`
			functionCache[cacheName] = true
		end
	end

	for location in src:gmatch("%s()function%s+[%w_]+[%.:]") do
		local signature = FunctionParser.ParseSignature(src, location)
		if not signature then
			-- print("failed to get signature?")
			-- print(src:sub(location, location + 64))
			continue
		end
		-- Ignore functions starting with _ that aren't explictly documented
		if signature.name:match("[%.:]_[_%w]*$") then continue end

		local within = signature.name:match("^([%w_]+)[%.:]")
		local funcName = signature.name:match("[%.:]([%w_]+)$")
		local cacheName = `{within}/{funcName}`
		if functionCache[cacheName] then continue end

		local fcomment: ParsedComment = {
			__start = location,
			__end = signature.__raw.finish,
			__commentType = "Dashed",
			param = {},
			["return"] = {},
			error = {},
		} :: ParsedComment
		if Parser.ApplyFunctionInfo(fcomment, signature, classIndex) then
			table.insert(results, fcomment)
			functionCache[cacheName] = true
		end
	end

	for _, result in pairs(results) do
		result.__source = nil
	end

	return results
end

export type EditableScript = Script | ModuleScript | LocalScript
-- Wrapper around Parser.ReadSource that replaces `result.__source` with `source`
function Parser.ReadScript(source: EditableScript) : {ParsedComment}
	local results = Parser.ReadSource(source.Source)
	for _, result in pairs(results) do
		result.__source = source
	end

	return results
end
return Parser
