local StringUtils = require "./StringUtils"
local termite = if game then require(script.Parent.External.termite) else require "../external/termite/src"
local LuauGrammar = require "./LuauGrammar"

export type FunctionSignature = {
    name: string,
    funcType: "function" | "method",
    genericTypeParams: {string},
    params: {{
        name: string,
        luaType: string?,
    }},
    returns: {string},
    __raw: typeof(termite.parse())
}

local FunctionParser = {}

function FunctionParser.ParseSignature(source: string, init: number) : FunctionSignature?
    local success, pair = pcall(termite.parse, LuauGrammar, source:sub(init), "FUNC_SIGNATURE")
    if not success then
        return nil
    end

    local name = pair.inner[1]
    local genericTypeParams = {}
    local params = {}
    local returns = {}
    local isMethod = #name.inner > 0 and name.inner[#name.inner].rule == "METHOD_NAME"

    for _, inner in pair.inner do
        if inner.rule == "GenericTypeList" then
            for _, param in inner.inner do
                table.insert(genericTypeParams, param:asString())
            end
        elseif inner.rule == "parlist" then
            local parlist = inner
            if parlist.inner[1].rule == "VARARGS" then
                table.insert(params, {
                    name = "...",
                    luaType = if parlist.inner[2] ~= nil then parlist.inner[2]:asString() else nil
                })
            elseif parlist.inner[1].rule == "bindinglist" then
                for _, binding in parlist.inner[1].inner do
                    table.insert(params, {
                        name = binding.inner[1]:asString(),
                        luaType = if binding.inner[2] then binding.inner[2]:asString() else nil
                    })
                end
                if parlist.inner[2] then
                    table.insert(params, {
                        name = "...",
                        luaType = if parlist.inner[3] ~= nil then parlist.inner[3]:asString() else nil
                    })
                end
            end
        elseif inner.rule == "ReturnType" then
            local rt = inner.inner[1]
            if rt.rule == "TypePack" then
                local typeList = rt.inner[1]
                if typeList then
                    for _, r in typeList.inner do
                        table.insert(returns, StringUtils.TrimWhitespace(r:asString()))
                    end
                end
            else
                table.insert(returns, StringUtils.TrimWhitespace(inner:asString()))
            end
        end
    end

    return {
        name = name:asString(),
        funcType = if isMethod then "method" else "function",
        genericTypeParams = genericTypeParams,
        params = params,
        returns = returns,
        __raw = pair,
    }
end

return FunctionParser
