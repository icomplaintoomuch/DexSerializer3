

local SaveInstance = {}
local API = {}
local Settings = {
    Decompile = true,
    DecompileTimeout = 10,
    MaxThreads = 4,
    Binary = true,
    IgnoreDefaultProps = true,
    SavePlayers = false,
    RemovePlayerCharacters = true,
    IsolateStarterPlayer = true,
    NilInstances = false,
    ShowStatus = true,
    FileName = nil
}


local env = {
    writefile = writefile,
    appendfile = appendfile,
    makefolder = makefolder,
    isfolder = isfolder,
    isfile = isfile,
    gethiddenproperty = gethiddenproperty or gethiddenprop,
    sethiddenproperty = sethiddenproperty or sethiddenprop,
    getcustomproperty = getcustomproperty,
    getscriptbytecode = getscriptbytecode,
    decompile = decompile,
    getnilinstances = getnilinstances or get_nil_instances,
    lz4compress = lz4compress or (syn and syn.crypt and syn.crypt.lz4 and syn.crypt.lz4.compress),
    base64encode = (crypt and crypt.base64encode) or base64encode or (syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.encode),
    request = request or syn and syn.request or http and http.request,
    getgenv = getgenv,
}

if not env.gethiddenproperty and getproperties then
    env.gethiddenproperty = function(obj, prop)
        local props = getproperties(obj)
        return props and props[prop]
    end
end
local function getScriptSource(scriptObj, timeout)
    timeout = timeout or Settings.DecompileTimeout
    
    if env.decompile then
        local ok, result, err = pcall(function()
            if elysianexecute then
                local thread = coroutine.running()
                local finished = false
                local success, derr = pcall(decompile, scriptObj, function(src, errorMsg)
                    if not finished then
                        finished = true
                        coroutine.resume(thread, src, errorMsg)
                    end
                end, timeout)
                if not success then return nil, derr end

                task.delay(timeout + 1, function()
                    if not finished then
                        finished = true
                        coroutine.resume(thread, nil, "decompiler timed out")
                    end
                end)
                return coroutine.yield()
            else
                return decompile(scriptObj, nil, timeout)
            end
        end)
        if ok and result and #result > 0 then
            return result
        end
    end
    
    if env.gethiddenproperty then
        local ok, result = pcall(env.gethiddenproperty, scriptObj, "Source")
        if ok and result and type(result) == "string" and #result > 0 then
            return result
        end
    end

    if env.getcustomproperty then
        local ok, result = pcall(env.getcustomproperty, scriptObj, "Source")
        if ok and result and type(result) == "string" and #result > 0 then
            return result
        end
    end
    
    if env.getscriptbytecode and env.request and env.base64encode then
        local ok, bytecode = pcall(getscriptbytecode, scriptObj)
        if ok and bytecode and #bytecode > 0 then
            local reqOk, response = pcall(env.request, {
                Url = "https://api.lua.expert/decompile",
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = game:GetService("HttpService"):JSONEncode({
                    script = env.base64encode(bytecode)
                })
            })
            if reqOk and response and response.StatusCode == 200 and response.Body then
                local bodyOk, decoded = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), response.Body)
                if bodyOk and decoded and decoded.source then
                    return decoded.source
                elseif not bodyOk and response.Body then
                    return response.Body
                end
            end
        end
    end
    
    return nil, "all script source methods exhausted"
end

local function decompileScripts(scripts, statusCallback)
    if not Settings.Decompile or #scripts == 0 then return {} end
    
    local sources = {}
    local queue = {}
    for i, v in ipairs(scripts) do queue[i] = v end
    
    local completed = 0
    local total = #queue
    local left = total
    local lock = false
    
    local function worker()
        while true do
            local scr = nil
            while lock do task.wait() end
            lock = true
            scr = table.remove(queue)
            lock = false
            
            if not scr then break end
            
            local source, err = getScriptSource(scr, Settings.DecompileTimeout)
            if source then
                sources[scr] = source
            else
                sources[scr] = "failed to retrieve source: " .. (err or "Unknown error")
            end
            
            completed = completed + 1
            left = left - 1
            
            if statusCallback then
                statusCallback(string.format("Decompiling... (%d/%d)", completed, total))
            end
        end
    end
    
    local threads = math.min(Settings.MaxThreads, total)
    for i = 1, threads do
        task.spawn(worker)
    end

    while left > 0 do task.wait() end
    return sources
end


local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local xmlReplace = {["'"] = "&apos;", ['"'] = "&quot;", ["<"] = "&lt;", [">"] = "&gt;", ["&"] = "&amp;", ["\0"] = ""}
local xmlPattern = "['\"<>&\0]"

local function escapeXml(str)
    return string.gsub(str, xmlPattern, xmlReplace)
end

local valueConverters = {
    bool = function(name, val) return string.format('\n<bool name="%s">%s</bool>', name, tostring(val)) end,
    int = function(name, val) return string.format('\n<int name="%s">%d</int>', name, val) end,
    float = function(name, val) return string.format('\n<float name="%s">%.12f</float>', name, val) end,
    double = function(name, val) return string.format('\n<double name="%s">%.12f</double>', name, val) end,
    string = function(name, val) return string.format('\n<string name="%s">%s</string>', name, escapeXml(val)) end,
    BrickColor = function(name, val) return string.format('\n<int name="%s">%d</int>', name, val.Number) end,
    Vector2 = function(name, val) 
        return string.format('\n<Vector2 name="%s">\n<X>%.12f</X>\n<Y>%.12f</Y>\n</Vector2>', name, val.X, val.Y) 
    end,
    Vector3 = function(name, val)
        return string.format('\n<Vector3 name="%s">\n<X>%.12f</X>\n<Y>%.12f</Y>\n<Z>%.12f</Z>\n</Vector3>', name, val.X, val.Y, val.Z)
    end,
    CFrame = function(name, val)
        local comps = {val:GetComponents()}
        return string.format('\n<CoordinateFrame name="%s">\n<X>%.12f</X>\n<Y>%.12f</Y>\n<Z>%.12f</Z>\n<R00>%.12f</R00>\n<R01>%.12f</R01>\n<R02>%.12f</R02>\n<R10>%.12f</R10>\n<R11>%.12f</R11>\n<R12>%.12f</R12>\n<R20>%.12f</R20>\n<R21>%.12f</R21>\n<R22>%.12f</R22>\n</CoordinateFrame>', 
            name, comps[1], comps[2], comps[3], comps[4], comps[5], comps[6], comps[7], comps[8], comps[9], comps[10], comps[11], comps[12])
    end,
    Color3 = function(name, val)
        return string.format('\n<Color3 name="%s">\n<R>%.12f</R>\n<G>%.12f</G>\n<B>%.12f</B>\n</Color3>', name, val.R, val.G, val.B)
    end,
    UDim = function(name, val)
        return string.format('\n<UDim name="%s">\n<S>%.12f</S>\n<O>%d</O>\n</UDim>', name, val.Scale, val.Offset)
    end,
    UDim2 = function(name, val)
        return string.format('\n<UDim2 name="%s">\n<XS>%.12f</XS>\n<XO>%d</XO>\n<YS>%.12f</YS>\n<YO>%d</YO>\n</UDim2>', name, val.X.Scale, val.X.Offset, val.Y.Scale, val.Y.Offset)
    end,
    Content = function(name, val)
        return string.format('\n<Content name="%s"><url>%s</url></Content>', name, escapeXml(val))
    end,
    PhysicalProperties = function(name, val)
        if val then
            return string.format('\n<PhysicalProperties name="%s">\n<CustomPhysics>true</CustomPhysics>\n<Density>%.12f</Density>\n<Friction>%.12f</Friction>\n<Elasticity>%.12f</Elasticity>\n<FrictionWeight>%.12f</FrictionWeight>\n<ElasticityWeight>%.12f</ElasticityWeight>\n</PhysicalProperties>',
                name, val.Density, val.Friction, val.Elasticity, val.FrictionWeight, val.ElasticityWeight)
        else
            return string.format('\n<PhysicalProperties name="%s">\n<CustomPhysics>false</CustomPhysics>\n</PhysicalProperties>', name)
        end
    end,
    Enum = function(name, val)
        return string.format('\n<token name="%s">%d</token>', name, val.Value)
    end,
    NumberRange = function(name, val)
        return string.format('\n<NumberRange name="%s">%s</NumberRange>', name, tostring(val))
    end,
    NumberSequence = function(name, val)
        return string.format('\n<NumberSequence name="%s">%s</NumberSequence>', name, tostring(val))
    end,
    ColorSequence = function(name, val)
        return string.format('\n<ColorSequence name="%s">%s</ColorSequence>', name, tostring(val))
    end,
    Rect = function(name, val)
        return string.format('\n<Rect2D name="%s">\n<min>\n<X>%.12f</X>\n<Y>%.12f</Y>\n</min>\n<max>\n<X>%.12f</X>\n<Y>%.12f</Y>\n</max>\n</Rect2D>', name, val.Min.X, val.Min.Y, val.Max.X, val.Max.Y)
    end,
    Faces = function(name, val)
        local faceInt = (val.Front and 32 or 0) + (val.Bottom and 16 or 0) + (val.Left and 8 or 0) + (val.Back and 4 or 0) + (val.Top and 2 or 0) + (val.Right and 1 or 0)
        return string.format('\n<Faces name="%s">\n<faces>%d</faces>\n</Faces>', name, faceInt)
    end,
    Axes = function(name, val)
        local axisInt = (val.Z and 4 or 0) + (val.Y and 2 or 0) + (val.X and 1 or 0)
        return string.format('\n<Axes name="%s">\n<axes>%d</axes>\n</Axes>', name, axisInt)
    end,
    Ray = function(name, val)
        return string.format('\n<Ray name="%s">\n<origin>\n<X>%.12f</X>\n<Y>%.12f</Y>\n<Z>%.12f</Z>\n</origin>\n<direction>\n<X>%.12f</X>\n<Y>%.12f</Y>\n<Z>%.12f</Z>\n</direction>\n</Ray>',
            name, val.Origin.X, val.Origin.Y, val.Origin.Z, val.Direction.X, val.Direction.Y, val.Direction.Z)
    end,
}


local function fetchAPI()
    local apiUrl = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/Full-API-Dump.json"
    local success, result = pcall(function()
        if RunService:IsStudio() then
            return require(game.ReplicatedStorage:FindFirstChild("FullAPI") or game.ReplicatedStorage:FindFirstChild("API"))
        else
            return game:HttpGet(apiUrl)
        end
    end)
    
    if not success then return nil, result end
    
    local decoded
    if type(result) == "string" then
        local ok, res = pcall(HttpService.JSONDecode, HttpService, result)
        if not ok then return nil, res end
        decoded = res
    else
        decoded = result
    end
    
    local classes = {}
    for _, class in ipairs(decoded.Classes) do
        local newClass = {
            Name = class.Name,
            Superclass = class.Superclass,
            Properties = {},
            Tags = {}
        }
        if class.Tags then
            for _, tag in ipairs(class.Tags) do newClass.Tags[tag] = true end
        end
        for _, member in ipairs(class.Members or {}) do
            if member.MemberType == "Property" then
                table.insert(newClass.Properties, {
                    Name = member.Name,
                    ValueType = member.ValueType,
                    Serialization = member.Serialization,
                    Tags = member.Tags or {},
                    Category = member.Category
                })
            end
        end
        classes[class.Name] = newClass
    end

    for name, class in pairs(classes) do
        if class.Superclass and classes[class.Superclass] then
            class.Superclass = classes[class.Superclass]
        else
            class.Superclass = nil
        end
    end
    
    return {Classes = classes}
end


local savePropsCache = {}
local testInstCache = {}

local function getSaveProps(obj, class, apiClasses)
    if savePropsCache[class] then return savePropsCache[class] end
    
    local result = {}
    local curClass = apiClasses[class]
    
    while curClass do
        for _, prop in ipairs(curClass.Properties) do
            if prop.Serialization and prop.Serialization.CanSave then
                local exists = false
                if prop.Tags and table.find(prop.Tags, "NotScriptable") then
                    if env.gethiddenproperty then
                        exists = pcall(function() env.gethiddenproperty(obj, prop.Name) end)
                    end
                else
                    exists = pcall(function() return obj[prop.Name] end)
                end
                
                if exists then
                    table.insert(result, prop)
                end
            end
        end
        curClass = curClass.Superclass
    end
    
    if class == "Script" or class == "LocalScript" or class == "ModuleScript" then
        table.insert(result, {
            Name = "Source",
            ValueType = {Name = "ProtectedString", Category = "DataType"},
            Special = "Source"
        })
    end
    
    table.sort(result, function(a, b) return a.Name < b.Name end)
    savePropsCache[class] = result
    return result
end

local function getTestInst(class, apiClasses)
    if testInstCache[class] then return testInstCache[class] end
    if Settings.IgnoreDefaultProps then
        testInstCache[class] = {}
        return {}
    end
    
    local ok, inst = pcall(Instance.new, class)
    if not ok then
        testInstCache[class] = {}
        return {}
    end
    
    local defaults = {}
    local props = savePropsCache[class] or {}
    for _, prop in ipairs(props) do
        if not prop.Special then
            local getOk, val = pcall(function() return inst[prop.Name] end)
            if getOk then defaults[prop.Name] = val end
        end
    end
    
    testInstCache[class] = defaults
    pcall(function() inst:Destroy() end)
    return defaults
end



function SaveInstance.SaveXML(root, fileName, opts)
    if opts then for k, v in pairs(opts) do Settings[k] = v end end
    
    local isGame = (root == game)
    local isTable = (type(root) == "table")
    if isTable and (not root[1]) then error("Empty table") end
    
    if not fileName then
        fileName = isGame and ("Place_" .. game.PlaceId .. ".rbxlx") or ("Model_" .. game.PlaceId .. ".rbxmx")
    end
    
    if isGame and not fileName:match("%.rbxlx?$") then fileName = fileName .. ".rbxlx" end
    if not isGame and not fileName:match("%.rbxmx?$") then fileName = fileName .. ".rbxmx" end
    
    if env.writefile then env.writefile(fileName, "") end
    
    local apiData, apiErr = fetchAPI()
    if not apiData then
        warn("API Fetch failed:", apiErr)
        apiData = {Classes = {}} 
    end
    local apiClasses = apiData.Classes
    
    local scriptsToDecompile = {}
    local sources = {}
    
    if Settings.Decompile then
        local targets = isTable and root or {root}
        for _, t in ipairs(targets) do
            for _, desc in ipairs(t:GetDescendants()) do
                if desc:IsA("LocalScript") or desc:IsA("ModuleScript") or desc:IsA("Script") then
                    table.insert(scriptsToDecompile, desc)
                end
            end
            if t:IsA("LocalScript") or t:IsA("ModuleScript") or t:IsA("Script") then
                table.insert(scriptsToDecompile, t)
            end
        end
        

        local statusText
        if Settings.ShowStatus and Drawing then
            statusText = Drawing.new("Text")
            statusText.Size = 24
            statusText.Color = Color3.new(1, 1, 1)
            statusText.Outline = true
            statusText.Position = Vector2.new(20, 20)
            statusText.Visible = true
        end
        
        sources = decompileScripts(scriptsToDecompile, function(msg)
            if statusText then statusText.Text = msg end
            print(msg)
        end)
        
        if statusText then task.delay(3, function() statusText:Remove() end) end
    end
    

    local filter = {}
    if isGame and not Settings.SavePlayers then
        for _, plr in ipairs(Players:GetPlayers()) do
            filter[plr] = true
            if Settings.RemovePlayerCharacters and plr.Character then
                filter[plr.Character] = true
            end
        end
    end
    
    local serviceBlacklist = {CoreGui = true, CorePackages = true}
    local folderClasses = {Player = true, PlayerScripts = true, PlayerGui = true}
    if Settings.IsolateStarterPlayer then
        folderClasses.StarterPlayer = true
        folderClasses.StarterCharacterScripts = true
        folderClasses.StarterPlayerScripts = true
    end
    

    local buffer = {
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">',
        '\n<Meta name="ExplicitAutoJoints">true</Meta>',
        '\n<External>null</External>',
        '\n<External>nil</External>'
    }
    
    local refs = {}
    local refCount = 1
    
    local function addToBuffer(str)
        table.insert(buffer, str)
        if #buffer > 8000 then
            if env.appendfile then env.appendfile(fileName, table.concat(buffer)) end
            table.clear(buffer)
        end
    end
    
    local function serializeObject(obj)
        if filter[obj] then return end
        
        local class = obj.ClassName
        if folderClasses[class] then class = "Folder" end
        
        local ref = refs[obj]
        if not ref then
            ref = refCount
            refs[obj] = ref
            refCount = refCount + 1
        end
        
        local props = getSaveProps(obj, class, apiClasses)
        local testInst = getTestInst(class, apiClasses)
        
        addToBuffer(string.format('\n<Item class="%s" referent="RBX%d">\n<Properties>', class, ref))
        

        if not testInst["Name"] or testInst["Name"] ~= obj.Name then
            addToBuffer(string.format('\n<string name="Name">%s</string>', escapeXml(obj.Name)))
        end
        
        for _, prop in ipairs(props) do
            local propName = prop.Name
            if propName == "Name" then continue end
            
            local propVal
            local shouldSave = false
            
            if prop.Special == "Source" then
                if sources[obj] then
                    propVal = sources[obj]
                    shouldSave = true
                elseif Settings.Decompile then
                    propVal = "failed to decompile"
                    shouldSave = true
                end
            elseif prop.Tags and table.find(prop.Tags, "NotScriptable") then
                if env.gethiddenproperty then
                    local ok, val = pcall(env.gethiddenproperty, obj, propName)
                    if ok then
                        propVal = val
                        shouldSave = true
                    end
                end
            else
                local ok, val = pcall(function() return obj[propName] end)
                if ok then
                    propVal = val
                    shouldSave = true
                end
            end
            
            if shouldSave and (Settings.IgnoreDefaultProps or testInst[propName] ~= propVal) then
                local converter = valueConverters[prop.ValueType.Name] or valueConverters[prop.ValueType.Category]
                if converter then
                    addToBuffer(converter(propName, propVal))
                elseif prop.ValueType.Category == "Enum" then
                    addToBuffer(string.format('\n<token name="%s">%d</token>', propName, propVal.Value))
                elseif typeof(propVal) == "Instance" and propVal then
                    local childRef = refs[propVal] or refCount
                    if not refs[propVal] then
                        refs[propVal] = childRef
                        refCount = refCount + 1
                    end
                    addToBuffer(string.format('\n<Ref name="%s">RBX%d</Ref>', propName, childRef))
                end
            end
        end
        
        addToBuffer('\n</Properties>')
        
        for _, child in ipairs(obj:GetChildren()) do
            serializeObject(child)
        end
        
        addToBuffer('\n</Item>')
    end

    if isGame then
        for _, child in ipairs(game:GetChildren()) do
            if not serviceBlacklist[child.ClassName] then
                serializeObject(child)
            end
        end
    elseif isTable then
        for _, obj in ipairs(root) do
            serializeObject(obj)
        end
    else
        serializeObject(root)
    end
    
    addToBuffer('\n</roblox>')
    
    if env.appendfile then env.appendfile(fileName, table.concat(buffer)) end
    print("Saved to " .. fileName)
    return fileName
end

function SaveInstance.SaveBinary(root, fileName, opts)
    warn("Binary mode: using XML fallback. Implement full binary chunk writing for .rbxl support.")
    return SaveInstance.SaveXML(root, fileName, opts)
end

function SaveInstance.Save(root, fileName, opts)
    root = root or game
    if opts then for k, v in pairs(opts) do Settings[k] = v end end
    
    if Settings.Binary then
        return SaveInstance.SaveBinary(root, fileName, opts)
    else
        return SaveInstance.SaveXML(root, fileName, opts)
    end
end
if getgenv then
    getgenv().saveinstance = SaveInstance.Save
    getgenv().SaveInstance = SaveInstance
end

return SaveInstance
