--[[
    Potassium ServerStorage & ServerScriptService Serializer
    Usage:
        local S = loadstring(script)()
        S.Init()
        S.Save("MyServer.rbxl", {Decompile = true, MaxThreads = 3})
]]

local Serializer, API, saveProps, testInsts = {}, {}, {}, {}
local env, oldIndex, gameId

local service = setmetatable({}, {__index = function(self, name)
    local serv = game:GetService(name)
    self[name] = serv
    return serv
end})

local tostring = tostring
local format = string.format
local gsub = string.gsub
local sub = string.sub
local getChildren = game.GetChildren
local isa = game.IsA
local components = CFrame.new(0, 0, 0).GetComponents
local httpService = service.HttpService
local urlEncode = httpService.UrlEncode
local concat = table.concat
local s_pack = string.pack
local s_unpack = string.unpack
local lrotate = bit32.lrotate
local tableCreate = table.create
local select = select
local unpack = unpack
local split = string.split
local s_rep = string.rep

local propBypass = {
    ["BasePart"] = {["Color"] = true},
}

local propFilter = {
    ["BaseScript"] = {["LinkedSource"] = true},
    ["Script"] = {["Source"] = true},
    ["ModuleScript"] = {["LinkedSource"] = true, ["Source"] = true},
    ["Players"] = {["CharacterAutoLoads"] = true},
    ["BillboardGui"] = {["PlayerToHideFrom"] = true},
    ["Instance"] = {["SourceAssetId"] = true, ["PropertyStatusStudio"] = true},
    ["Model"] = {["WorldPivotData"] = true},
    ["TerrainRegion"] = {["ExtentsMax"] = true, ["ExtentsMin"] = true}
}

local binaryDataTypes = {
    ["string"] = 1,
    ["ContentId"] = 1,
    ["BinaryString"] = 1,
    ["bool"] = 2,
    ["int"] = 3,
    ["float"] = 4,
    ["double"] = 5,
    ["UDim"] = 6,
    ["UDim2"] = 7,
    ["Ray"] = 8,
    ["Faces"] = 9,
    ["Axes"] = 10,
    ["BrickColor"] = 11,
    ["Color3"] = 12,
    ["Vector2"] = 13,
    ["Vector3"] = 14,
    ["CFrame"] = 16,
    ["Enum"] = 18,
    ["Referent"] = 19,
    ["Vector3int16"] = 20,
    ["NumberSequence"] = 21,
    ["ColorSequence"] = 22,
    ["NumberRange"] = 23,
    ["Rect"] = 24,
    ["PhysicalProperties"] = 25,
    ["Color3uint8"] = 26,
    ["int64"] = 27,
    ["SharedString"] = 28,
    ["OptionalCoordinateFrame"] = 30,
    ["Font"] = 32
}

local binaryCFrameMap = {
    ["001286300000000000000128630000000000000012863"] = 2,
    ["0012863000000000000000000128191000000128630000"] = 3,
    ["00128630000000000000012819100000000000000128191"] = 5,
    ["001286300000001280000000000128630000001281910000"] = 6,
    ["0000001286300000012863000000000000000000128191"] = 7,
    ["000000000012863001286300000000000000128630000"] = 9,
    ["000000128191000000128630000000128000000000012863"] = 10,
    ["00000000001281910012863000000000000001281910000"] = 12,
    ["000000128630000000000000012863001286300000000"] = 13,
    ["0000000000128191000000128630000001286300000000"] = 14,
    ["00000012819100000000000000128191001286300000000"] = 16,
    ["000000000012863000000128191000000128630000000128"] = 17,
    ["00128191000000000000001286300000000000000128191"] = 20,
    ["001281910000000000000000001286300000012863000128"] = 21,
    ["00128191000000000000001281910000000000000012863"] = 23,
    ["0012819100000001280000000000128191000000128191000128"] = 24,
    ["000000128630001280012819100000000000000000012863"] = 25,
    ["00000000001281910012819100000000000000128630000"] = 27,
    ["0000001281910001280012819100000001280000000000128191"] = 28,
    ["00000000001286300128191000000000000001281910000"] = 30,
    ["00000012863000000000000001281910012819100000000"] = 31,
    ["000000000012863000000128630001280012819100000000"] = 32,
    ["00000012819100000000000000128630012819100000000"] = 34,
    ["0000000000128191000000128191000128001281910000000128"] = 35,
}

local binaryPropHandlers = {
    ["string"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            result[i] = s_pack("I4", #val) .. val
        end
        return concat(result)
    end,
    ["ContentId"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            result[i] = s_pack("I4", #val) .. val
        end
        return concat(result)
    end,
    ["BinaryString"] = function(objs, name, func)
        if not env.getbspval then return end
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val = env.getbspval(objs[i], name) or ""
            result[i] = s_pack("I4", #val) .. val
        end
        return concat(result)
    end,
    ["bool"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            result[i] = val and "\1" or "\0"
        end
        return concat(result)
    end,
    ["int"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(4 * szObjs)
        local sep = szObjs - 1
        for i = 1, szObjs do
            local start = i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local bytes = s_pack("I4", val < 0 and 2 * -val - 1 or 2 * val)
            for b = 1, 4 do
                result[start + b + sep * (b - 1)] = sub(bytes, b, b)
            end
        end
        return concat(result)
    end,
    ["float"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(4 * szObjs)
        local sep = szObjs - 1
        for i = 1, szObjs do
            local start = i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local bytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val)), 1))
            for b = 1, 4 do
                result[start + b + sep * (b - 1)] = sub(bytes, b, b)
            end
        end
        return concat(result)
    end,
    ["double"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            result[i] = s_pack("d", val)
        end
        return concat(result)
    end,
    ["UDim"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(2 * 4 * szObjs)
        local sep = szObjs - 1
        local firstArrayEnd = 4 * szObjs
        for i = 1, szObjs do
            local scaleStart = i - 1
            local offsetStart = firstArrayEnd + i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local offset = val.Offset
            local scaleBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.Scale)), 1))
            local offsetBytes = s_pack("I4", offset < 0 and 2 * -offset - 1 or 2 * offset)
            for b = 1, 4 do
                result[scaleStart + b + sep * (b - 1)] = sub(scaleBytes, b, b)
                result[offsetStart + b + sep * (b - 1)] = sub(offsetBytes, b, b)
            end
        end
        return concat(result)
    end,
    ["UDim2"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(4 * 4 * szObjs)
        local sep = szObjs - 1
        local firstArrayEnd = 4 * szObjs
        local secondArrayEnd = 2 * 4 * szObjs
        local thirdArrayEnd = 3 * 4 * szObjs
        for i = 1, szObjs do
            local xScaleStart = i - 1
            local yScaleStart = firstArrayEnd + i - 1
            local xOffsetStart = secondArrayEnd + i - 1
            local yOffsetStart = thirdArrayEnd + i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local x, y = val.X, val.Y
            local xOffset = x.Offset
            local yOffset = y.Offset
            local xScaleBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", x.Scale)), 1))
            local xOffsetBytes = s_pack("I4", xOffset < 0 and 2 * -xOffset - 1 or 2 * xOffset)
            local yScaleBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", y.Scale)), 1))
            local yOffsetBytes = s_pack("I4", yOffset < 0 and 2 * -yOffset - 1 or 2 * yOffset)
            for b = 1, 4 do
                result[xScaleStart + b + sep * (b - 1)] = sub(xScaleBytes, b, b)
                result[xOffsetStart + b + sep * (b - 1)] = sub(xOffsetBytes, b, b)
                result[yScaleStart + b + sep * (b - 1)] = sub(yScaleBytes, b, b)
                result[yOffsetStart + b + sep * (b - 1)] = sub(yOffsetBytes, b, b)
            end
        end
        return concat(result)
    end,
    ["Ray"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local origin = val.Origin
            local dir = val.Direction
            result[i] = s_pack("ffffff", origin.X, origin.Y, origin.Z, dir.X, dir.Y, dir.Z)
        end
        return concat(result)
    end,
    ["Faces"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local faceInt = (val.Front and 32 or 0) + (val.Bottom and 16 or 0) + (val.Left and 8 or 0) + (val.Back and 4 or 0) + (val.Top and 2 or 0) + (val.Right and 1 or 0)
            result[i] = s_pack("b", faceInt)
        end
        return concat(result)
    end,
    ["Axes"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local axisInt = (val.Z and 4 or 0) + (val.Y and 2 or 0) + (val.X and 1 or 0)
            result[i] = s_pack("b", axisInt)
        end
        return concat(result)
    end,
    ["BrickColor"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(4 * szObjs)
        local sep = szObjs - 1
        for i = 1, szObjs do
            local start = i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local bytes = s_pack("I4", val.Number)
            for b = 1, 4 do
                result[start + b + sep * (b - 1)] = sub(bytes, b, b)
            end
        end
        return concat(result)
    end,
    ["Color3"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(3 * 4 * szObjs)
        local sep = szObjs - 1
        local firstArrayEnd = 4 * szObjs
        local secondArrayEnd = 8 * szObjs
        for i = 1, szObjs do
            local rStart = i - 1
            local gStart = firstArrayEnd + i - 1
            local bStart = secondArrayEnd + i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local rBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.R)), 1))
            local gBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.G)), 1))
            local bBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.B)), 1))
            for b = 1, 4 do
                result[rStart + b + sep * (b - 1)] = sub(rBytes, b, b)
                result[gStart + b + sep * (b - 1)] = sub(gBytes, b, b)
                result[bStart + b + sep * (b - 1)] = sub(bBytes, b, b)
            end
        end
        return concat(result)
    end,
    ["Vector2"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(2 * 4 * szObjs)
        local sep = szObjs - 1
        local firstArrayEnd = 4 * szObjs
        for i = 1, szObjs do
            local xStart = i - 1
            local yStart = firstArrayEnd + i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local xBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.X)), 1))
            local yBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.Y)), 1))
            for b = 1, 4 do
                result[xStart + b + sep * (b - 1)] = sub(xBytes, b, b)
                result[yStart + b + sep * (b - 1)] = sub(yBytes, b, b)
            end
        end
        return concat(result)
    end,
    ["Vector3"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(3 * 4 * szObjs)
        local sep = szObjs - 1
        local firstArrayEnd = 4 * szObjs
        local secondArrayEnd = 8 * szObjs
        for i = 1, szObjs do
            local xStart = i - 1
            local yStart = firstArrayEnd + i - 1
            local zStart = secondArrayEnd + i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local xBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.X)), 1))
            local yBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.Y)), 1))
            local zBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", val.Z)), 1))
            for b = 1, 4 do
                result[xStart + b + sep * (b - 1)] = sub(xBytes, b, b)
                result[yStart + b + sep * (b - 1)] = sub(yBytes, b, b)
                result[zStart + b + sep * (b - 1)] = sub(zBytes, b, b)
            end
        end
        return concat(result)
    end,
    ["CFrame"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs + 3 * 4 * szObjs)
        local sep = szObjs - 1
        local posStart = szObjs
        local firstArrayEnd = posStart + 4 * szObjs
        local secondArrayEnd = posStart + 8 * szObjs
        for i = 1, szObjs do
            local xStart = posStart + i - 1
            local yStart = firstArrayEnd + i - 1
            local zStart = secondArrayEnd + i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local componentStr = s_pack("fffffffff", select(4, components(val)))
            result[i] = binaryCFrameMap[componentStr] or "\0" .. componentStr
            local pos = val.Position
            local xBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", pos.X)), 1))
            local yBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", pos.Y)), 1))
            local zBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", pos.Z)), 1))
            for b = 1, 4 do
                result[xStart + b + sep * (b - 1)] = sub(xBytes, b, b)
                result[yStart + b + sep * (b - 1)] = sub(yBytes, b, b)
                result[zStart + b + sep * (b - 1)] = sub(zBytes, b, b)
            end
        end
        return concat(result)
    end,
    ["Enum"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(4 * szObjs)
        local sep = szObjs - 1
        for i = 1, szObjs do
            local start = i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local bytes = s_pack("I4", val.Value)
            for b = 1, 4 do
                result[start + b + sep * (b - 1)] = sub(bytes, b, b)
            end
        end
        return concat(result)
    end,
    ["Vector3int16"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            result[i] = s_pack("i2i2i2", val.X, val.Y, val.Z)
        end
        return concat(result)
    end,
    ["NumberSequence"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local numKeypoints = #val.Keypoints
            result[i] = s_pack("I4" .. s_rep("fff", numKeypoints), numKeypoints, unpack(split(tostring(val), " ")))
        end
        return concat(result)
    end,
    ["ColorSequence"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local numKeypoints = #val.Keypoints
            result[i] = s_pack("I4" .. s_rep("fffff", numKeypoints), numKeypoints, unpack(split(tostring(val), " ")))
        end
        return concat(result)
    end,
    ["NumberRange"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            result[i] = s_pack("ff", val.Min, val.Max)
        end
        return concat(result)
    end,
    ["Rect"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(4 * 4 * szObjs)
        local sep = szObjs - 1
        local firstArrayEnd = 4 * szObjs
        local secondArrayEnd = 2 * 4 * szObjs
        local thirdArrayEnd = 3 * 4 * szObjs
        for i = 1, szObjs do
            local xMinStart = i - 1
            local yMinStart = firstArrayEnd + i - 1
            local xMaxStart = secondArrayEnd + i - 1
            local yMaxStart = thirdArrayEnd + i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local min = val.Min
            local max = val.Max
            local xMinBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", min.X)), 1))
            local yMinBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", min.Y)), 1))
            local xMaxBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", max.X)), 1))
            local yMaxBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", max.Y)), 1))
            for b = 1, 4 do
                result[xMinStart + b + sep * (b - 1)] = sub(xMinBytes, b, b)
                result[yMinStart + b + sep * (b - 1)] = sub(yMinBytes, b, b)
                result[xMaxStart + b + sep * (b - 1)] = sub(xMaxBytes, b, b)
                result[yMaxStart + b + sep * (b - 1)] = sub(yMaxBytes, b, b)
            end
        end
        return concat(result)
    end,
    ["PhysicalProperties"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            if val then
                result[i] = "\1" .. s_pack("fffff", val.Density, val.Friction, val.Elasticity, val.FrictionWeight, val.ElasticityWeight)
            else
                result[i] = "\0"
            end
        end
        return concat(result)
    end,
    ["Color3uint8"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            result[i] = "\1" .. s_pack("bbb", val.R, val.G, val.B)
        end
        return concat(result)
    end,
    ["int64"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(8 * szObjs)
        local sep = szObjs - 1
        for i = 1, szObjs do
            local start = i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local bytes = s_pack("I8", val < 0 and 2 * -val - 1 or 2 * val)
            for b = 1, 8 do
                result[start + b + sep * (b - 1)] = sub(bytes, b, b)
            end
        end
        return concat(result)
    end,
    ["OptionalCoordinateFrame"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(1 + szObjs + 3 * 4 * szObjs + 1 + szObjs)
        local sep = szObjs - 1
        local posStart = szObjs
        local firstArrayEnd = posStart + 4 * szObjs
        local secondArrayEnd = posStart + 8 * szObjs
        local thirdArrayEnd = posStart + 12 * szObjs
        local startOffset = 1
        result[1] = "\16"
        result[startOffset + thirdArrayEnd + 1] = "\2"
        for i = 1, szObjs do
            local xStart = startOffset + posStart + i - 1
            local yStart = startOffset + firstArrayEnd + i - 1
            local zStart = startOffset + secondArrayEnd + i - 1
            local boolPos = startOffset + thirdArrayEnd + i + 1
            local val, exists
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            if not val then exists = false; val = CFrame.new() else exists = true end
            local componentStr = s_pack("fffffffff", select(4, components(val)))
            result[startOffset + i] = binaryCFrameMap[componentStr] or "\0" .. componentStr
            local pos = val.Position
            local xBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", pos.X)), 1))
            local yBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", pos.Y)), 1))
            local zBytes = s_pack("I4", lrotate(s_unpack("I4", s_pack("f", pos.Z)), 1))
            for b = 1, 4 do
                result[xStart + b + sep * (b - 1)] = sub(xBytes, b, b)
                result[yStart + b + sep * (b - 1)] = sub(yBytes, b, b)
                result[zStart + b + sep * (b - 1)] = sub(zBytes, b, b)
            end
            result[boolPos] = exists and "\1" or "\0"
        end
        return concat(result)
    end,
    ["Font"] = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local family = s_pack("I4", #val.Family) .. val.Family
            local weight = s_pack("I2", val.Weight.Value)
            local style = s_pack("I1", val.Style.Value)
            local cached = "\0\0\0\0"
            result[i] = family .. weight .. style .. cached
        end
        return concat(result)
    end,
}

local specialProps = {
    ["Script"] = {
        {Name = "Source", ValueType = {Name = "ProtectedString", Category = "DataType"}, Special = "Decompile"}
    },
    ["ModuleScript"] = {
        {Name = "Source", ValueType = {Name = "ProtectedString", Category = "DataType"}, Special = "Decompile"}
    },
}

local function getSaveProps(obj, class)
    local result = {}
    local count = 1
    local curClass = API.Classes[class]
    while curClass do
        local curClassName = curClass.Name
        local cacheProps = saveProps[curClassName]
        if cacheProps then
            table.move(cacheProps, 1, #cacheProps, #result + 1, result)
            break
        end
        local props = curClass.Properties
        for i = 1, #props do
            local prop = props[i]
            local propName = prop.Name
            if prop.Serialization.CanSave or (propBypass[curClassName] and propBypass[curClassName][propName]) then
                if not propFilter[curClassName] or not propFilter[curClassName][propName] then
                    if prop.Tags and prop.Tags.NotScriptable then
                        local s, ret1, ret2 = pcall(env.gethiddenprop, obj, propName)
                        if s and type(ret2) ~= "string" then
                            result[count] = prop
                            count = count + 1
                        end
                    else
                        local s, e = pcall(function() return obj[propName] end)
                        if s then
                            result[count] = prop
                            count = count + 1
                        end
                    end
                end
            end
        end
        local special = specialProps[curClassName]
        if special then
            table.move(special, 1, #special, #result + 1, result)
            count = #result + 1
        end
        curClass = curClass.Superclass
    end
    table.sort(result, function(a, b) return a.Name < b.Name end)
    return result
end

local function getTestInst(class)
    local s, inst = pcall(Instance.new, class)
    if not s then return {} end
    local defaultProps = {}
    local props = saveProps[class]
    for i = 1, #props do
        local prop = props[i]
        if not prop.Special and not (prop.Tags and prop.Tags.NotScriptable) then
            local propName = prop.IndexName or prop.Name
            defaultProps[propName] = inst[propName]
        end
    end
    return defaultProps
end

local function doDecompile(scr)
    local success, result = pcall(function()
        return decompile(scr)
    end)
    if success and result then
        return result
    else
        return nil, result or "decompile failed"
    end
end

local function predecompile(roots, decompileEnabled, maxThreads)
    if not decompileEnabled then return {} end
    local scripts, sources, checked = {}, {}, {}
    local scriptCount, totalScripts = 1, 0
    
    for r = 1, #roots do
        local descs = roots[r]:GetDescendants()
        descs[0] = roots[r]
        for j = 0, #descs do
            local obj = descs[j]
            if (isa(obj, "LocalScript") or isa(obj, "ModuleScript") or isa(obj, "Script")) and not checked[obj] then
                scripts[scriptCount] = obj
                scriptCount = scriptCount + 1
                checked[obj] = true
            end
        end
    end
    
    totalScripts = scriptCount - 1
    local left = totalScripts
    maxThreads = maxThreads or 3
    
    for i = 1, maxThreads do
        task.spawn(function()
            while #scripts > 0 do
                local nextScript = table.remove(scripts)
                local source, err = doDecompile(nextScript)
                if source then
                    sources[nextScript] = source
                else
                    sources[nextScript] = "-- Script failed to decompile or ignored"
                end
                left = left - 1
            end
        end)
    end
    while left > 0 do task.wait() end
    return sources
end

local function serializeBinary(roots, filename, decompileEnabled, maxThreads)
    local mainBuf = {}
    local header = {string.char(60, 114, 111, 98, 108, 111, 120, 32, 98, 105, 110, 97, 114, 121, 32, 0, 0, 0, 0)}
    local metaBuf = {string.char(77, 69, 84, 65, 32, 0, 0, 3, 4, 0, 0, 0, 0, 2, 4, 0, 19, 1, 0, 0, 1, 8, 0, 0, 6, 9, 12, 0, 1, 12, 1, 0, 8, 10, 5, 9, 9, 10, 5, 10, 5, 11, 6, 6, 5, 11, 7, 1, 1, 6, 1, 1, 1, 0, 1, 1, 0, 1, 1, 6, 1, 1, 4, 0, 0, 1, 1, 6, 1, 1, 4, 1, 1, 7, 1, 0, 1)}
    local sstrBuf = {}
    local instBuf, instBufCount = {}, 1
    local propBuf, propBufCount = {}, 1
    local prntBuf = {}
    local endBuf = {string.char(69, 78, 68, 0, 0, 0, 0, 9, 0, 0, 0, 0, 6, 0, 4, 114, 111, 98, 108, 111, 120, 62)}
    local instTypeCount = 0
    local instCount = 0
    local refCount = 0
    local sharedStringCount = 0
    local startB = tick()
    local classList = {}
    local hashs = {}
    local sharedStrings = {}
    local refs = {}
    local parents = {}
    local orderedInstList = {}
    local savingDefaultProps = true
    
    if not filename then
        filename = "ServerStorage_ServerScriptService_" .. game.PlaceId .. ".rbxl"
    else
        filename = filename:match("%.rbxl$") and filename or filename .. ".rbxl"
    end
    
    env.writefile(filename, "")
    
    local sources = predecompile(roots, decompileEnabled, maxThreads)
    
    local function recur(obj, par)
        local class = oldIndex and oldIndex(obj, "ClassName") or obj.ClassName
        
        if not saveProps[class] then saveProps[class] = getSaveProps(obj, class) end
        if not testInsts[class] then testInsts[class] = getTestInst(class) end
        
        local ch = getChildren(obj)
        local szCh = #ch
        if szCh > 0 then
            for i = 1, szCh do
                local chObj = ch[i]
                parents[chObj] = obj
                recur(chObj)
            end
        end
        
        if not refs[obj] then
            instCount = instCount + 1
            orderedInstList[instCount] = obj
            local cList = classList[class]
            if not cList then
                cList = {}
                classList[class] = cList
                instTypeCount = instTypeCount + 1
            end
            cList[#cList + 1] = obj
            refs[obj] = refCount
            refCount = refCount + 1
        end
    end
    
    for i = 1, #roots do
        recur(roots[i])
    end
    
    local refPropHandler = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(4 * szObjs)
        local sep = szObjs - 1
        local lastRef
        for i = 1, szObjs do
            local start = i - 1
            local val
            if func then val = func(objs[i], name) elseif oldIndex then val = oldIndex(objs[i], name) else val = objs[i][name] end
            local ref = refs[val] or -1
            local accRef = lastRef and (ref - lastRef) or ref
            lastRef = ref
            local transformed = (accRef < 0 and 2 * -accRef - 1 or 2 * accRef)
            local bytes = s_pack("I4", transformed)
            for b = 1, 4 do
                result[start + b + sep * (b - 1)] = sub(bytes, b, b)
            end
        end
        return concat(result)
    end
    
    local sharedStringHandler = function(objs, name, func)
        if not env.gethiddenprop then return end
        if sharedStringCount == 0 then
            sharedStringCount = sharedStringCount + 1
            sharedStrings[1] = {"\0\0", ""}
        end
        local szObjs = #objs
        local result = tableCreate(4 * szObjs, "\0")
        local sep = szObjs - 1
        for i = 1, szObjs do
            local start = i - 1
            local content = env.gethiddenprop(objs[i], name)
            if content and #content > 0 then
                local hash = content
                local index = hashs[hash]
                if not index then
                    index = sharedStringCount
                    hashs[hash] = index
                    sharedStringCount = sharedStringCount + 1
                    sharedStrings[sharedStringCount] = {s_pack("I16", sharedStringCount), content}
                end
                local bytes = s_pack("I4", index)
                for b = 1, 4 do
                    result[start + b + sep * (b - 1)] = sub(bytes, b, b)
                end
            end
        end
        return concat(result)
    end
    
    local protectedStringHandler = function(objs, name, func)
        local szObjs = #objs
        local result = tableCreate(szObjs)
        for i = 1, szObjs do
            local val
            if sources[objs[i]] then
                val = sources[objs[i]]
            elseif not decompileEnabled then
                val = "-- Decompiling is disabled"
            else
                val = "-- Script failed to decompile or ignored"
            end
            result[i] = s_pack("I4", #val) .. val
        end
        return concat(result)
    end
    
    local typeId = 0
    for class, objs in next, classList do
        local instHeader = {"INST", string.rep("\0", 4), string.rep("\0", 4), string.rep("\0", 4)}
        local instChunkData = tableCreate(4 + 4 * #objs, "")
        local typeIdBytes = s_pack("I4", typeId)
        local isService = API.Classes[class] and API.Classes[class].Tags.Service
        instChunkData[1] = typeIdBytes
        instChunkData[2] = s_pack("I4", #class) .. class
        instChunkData[3] = isService and "\1" or "\0"
        instChunkData[4] = s_pack("I4", #objs)
        local lastRef
        local sep = #objs - 1
        for i = 1, #objs do
            local start = 4 + (i - 1)
            local obj = objs[i]
            local ref = refs[obj]
            local accRef = lastRef and (ref - lastRef) or ref
            lastRef = ref
            local transformed = (accRef < 0 and 2 * -accRef - 1 or 2 * accRef)
            local bytes = s_pack("I4", transformed)
            for b = 1, 4 do
                local chunkIndex = start + b + sep * (b - 1)
                instChunkData[chunkIndex] = sub(bytes, b, b)
            end
        end
        if isService then
            instChunkData[#instChunkData + 1] = s_rep("\1", #objs)
        end
        instChunkData = concat(instChunkData)
        instHeader[3] = s_pack("I4", #instChunkData)
        if env.lz4compress then
            instChunkData = env.lz4compress(instChunkData)
            instHeader[2] = s_pack("I4", #instChunkData)
        end
        instBuf[instBufCount] = concat(instHeader)
        instBuf[instBufCount + 1] = instChunkData
        instBufCount = instBufCount + 2
        
        local props = saveProps[class]
        for propInd = 1, #props do
            local prop = props[propInd]
            local propName = prop.Name
            local indexName = prop.IndexName or propName
            local typeData = prop.ValueType
            local propTypeCategory = typeData.Category
            local propType = typeData.Name
            local propHeader = {"PROP", string.rep("\0", 4), string.rep("\0", 4), string.rep("\0", 4)}
            local propChunkData = {typeIdBytes, s_pack("I4", #propName) .. propName, nil, ""}
            local handler
            if propTypeCategory == "Primitive" or propTypeCategory == "DataType" then
                handler = binaryPropHandlers[propType]
                propChunkData[3] = binaryDataTypes[propType]
                if not handler then
                    if propType == "SharedString" then
                        handler = sharedStringHandler
                    elseif propType == "ProtectedString" then
                        handler = protectedStringHandler
                        propChunkData[3] = binaryDataTypes["string"]
                    end
                end
            elseif propTypeCategory == "Enum" then
                handler = binaryPropHandlers["Enum"]
                propChunkData[3] = binaryDataTypes["Enum"]
            else
                handler = refPropHandler
                propChunkData[3] = binaryDataTypes["Referent"]
            end
            if handler then
                local func
                local special = prop.Special
                if prop.Tags and prop.Tags.NotScriptable then
                    if env.gethiddenprop then
                        func = env.gethiddenprop
                    else
                        continue
                    end
                end
                if special then
                    if special == "NotScriptable" then
                        if env.gethiddenprop then
                            func = env.gethiddenprop
                        else
                            continue
                        end
                    elseif special == "Func" then
                        func = prop.Func
                    end
                end
                local propData = handler(objs, indexName, func)
                if not propData then continue end
                propChunkData[4] = propData
                propChunkData = concat(propChunkData)
                propHeader[3] = s_pack("I4", #propChunkData)
                if env.lz4compress then
                    propChunkData = env.lz4compress(propChunkData)
                    propHeader[2] = s_pack("I4", #propChunkData)
                end
                propBuf[propBufCount] = concat(propHeader)
                propBuf[propBufCount + 1] = propChunkData
                propBufCount = propBufCount + 2
            end
        end
        typeId = typeId + 1
    end
    
    if sharedStringCount > 0 then
        local sstrHeader = {"SSTR", string.rep("\0", 4), string.rep("\0", 4), string.rep("\0", 4)}
        local sstrChunkData = {"\0\0\0\0", s_pack("I4", sharedStringCount)}
        local count = 3
        for i = 1, #sharedStrings do
            local data = sharedStrings[i]
            local hash, content = data[1], data[2]
            sstrChunkData[count] = hash .. s_pack("I4", #content) .. content
            count = count + 1
        end
        sstrChunkData = concat(sstrChunkData)
        sstrHeader[3] = s_pack("I4", #sstrChunkData)
        if env.lz4compress then
            sstrChunkData = env.lz4compress(sstrChunkData)
            sstrHeader[2] = s_pack("I4", #sstrChunkData)
        end
        sstrBuf[1] = concat(sstrHeader)
        sstrBuf[2] = sstrChunkData
    end
    
    local function makePRNT()
        local prntHeader = {"PRNT", string.rep("\0", 4), string.rep("\0", 4), string.rep("\0", 4)}
        local prntChunkData = tableCreate(2 + 2 * 4 * instCount)
        prntChunkData[1] = "\0"
        prntChunkData[2] = s_pack("I4", instCount)
        local lastObjRef, lastParRef
        local sep = instCount - 1
        local prntRefCount = 1
        local lastObjIndex = 2 + 4 * instCount
        for i = 1, instCount do
            local obj = orderedInstList[i]
            local ref = refs[obj]
            local objStart = 2 + (prntRefCount - 1)
            local parStart = lastObjIndex + (prntRefCount - 1)
            local par = parents[obj]
            local parRef = refs[par] or -1
            local accObjRef = lastObjRef and (ref - lastObjRef) or ref
            lastObjRef = ref
            local accParRef = lastParRef and (parRef - lastParRef) or parRef
            lastParRef = parRef
            local objTransformed = (accObjRef < 0 and 2 * -accObjRef - 1 or 2 * accObjRef)
            local objBytes = s_pack("I4", objTransformed)
            local parTransformed = (accParRef < 0 and 2 * -accParRef - 1 or 2 * accParRef)
            local parBytes = s_pack("I4", parTransformed)
            for b = 1, 4 do
                local objChunkIndex = objStart + b + sep * (b - 1)
                local parChunkIndex = parStart + b + sep * (b - 1)
                prntChunkData[objChunkIndex] = sub(objBytes, b, b)
                prntChunkData[parChunkIndex] = sub(parBytes, b, b)
            end
            prntRefCount = prntRefCount + 1
        end
        prntChunkData = concat(prntChunkData)
        prntHeader[3] = s_pack("I4", #prntChunkData)
        if env.lz4compress then
            prntChunkData = env.lz4compress(prntChunkData)
            prntHeader[2] = s_pack("I4", #prntChunkData)
        end
        prntBuf[1] = concat(prntHeader)
        prntBuf[2] = prntChunkData
    end
    makePRNT()
    
    header[2] = s_pack("i4", instTypeCount)
    header[3] = s_pack("i4", instCount)
    
    env.writefile(filename, concat(header))
    env.appendfile(filename, concat(metaBuf))
    env.appendfile(filename, concat(sstrBuf))
    env.appendfile(filename, concat(instBuf))
    env.appendfile(filename, concat(propBuf))
    env.appendfile(filename, concat(prntBuf))
    env.appendfile(filename, concat(endBuf))
    
    print("Saved " .. filename .. " in " .. (tick() - startB) .. " seconds")
end

local function fetchAPI()
    local rawAPI
    if game:GetService("RunService"):IsStudio() then
        rawAPI = require(game.ReplicatedStorage.FullAPI)
    else
        rawAPI = game:HttpGet("https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/Full-API-Dump.json")
    end
    
    local api = service.HttpService:JSONDecode(rawAPI)
    local classes, enums = {}, {}
    
    for _, class in pairs(api.Classes) do
        local newClass = {}
        newClass.Name = class.Name
        newClass.Superclass = classes[class.Superclass]
        newClass.Properties = {}
        newClass.Functions = {}
        newClass.Events = {}
        newClass.Callbacks = {}
        newClass.Tags = {}
        
        if class.Tags then for c, tag in pairs(class.Tags) do newClass.Tags[tag] = true end end
        
        for __, member in pairs(class.Members) do
            local newMember = {}
            newMember.Name = member.Name
            newMember.Class = class.Name
            newMember.Tags = {}
            if member.Tags then for c, tag in pairs(member.Tags) do newMember.Tags[tag] = true end end
            
            local mType = member.MemberType
            if mType == "Property" then
                newMember.ValueType = member.ValueType
                newMember.Category = member.Category
                newMember.Serialization = member.Serialization
                table.insert(newClass.Properties, newMember)
            end
        end
        
        classes[class.Name] = newClass
    end
    
    for _, enum in pairs(api.Enums) do
        local newEnum = {}
        newEnum.Name = enum.Name
        newEnum.Items = {}
        newEnum.Tags = {}
        if enum.Tags then for c, tag in pairs(enum.Tags) do newEnum.Tags[tag] = true end end
        for __, item in pairs(enum.Items) do
            local newItem = {}
            newItem.Name = item.Name
            newItem.Value = item.Value
            table.insert(newEnum.Items, newItem)
        end
        enums[enum.Name] = newEnum
    end
    
    return {Classes = classes, Enums = enums}
end

function Serializer.Init(oldInd)
    env = {} -- FIX: env was nil
    oldIndex = oldInd
    gameId = game.GameId
    
    env.writefile = writefile
    env.appendfile = appendfile
    env.gethiddenprop = gethiddenproperty
    env.getbspval = getbspval
    env.getpcd = getpcd
    env.lz4compress = (crypt and crypt.lz4compress) or lz4compress or nil
    env.encodeBase64 = (crypt and crypt.base64encode) or base64encode or nil
    env.hashmd5 = (crypt and function(s) return crypt.hash(s, "md5") end) or hashmd5 or nil
    
    if not env.getbspval and env.gethiddenprop and env.encodeBase64 then
        env.getbspval = function(obj, prop, enc)
            local binary = env.gethiddenprop(obj, prop) or ""
            if #binary == 0 then return nil end
            return enc and env.encodeBase64(binary) or binary
        end
    end
    
    local api = fetchAPI()
    API = api
end

function Serializer.Save(filename, opts)
    opts = opts or {}
    local roots = {game.ServerStorage, game.ServerScriptService}
    local decompileEnabled = opts.Decompile ~= false
    local maxThreads = opts.MaxThreads or 3
    
    serializeBinary(roots, filename, decompileEnabled, maxThreads)
end

return Serializer
