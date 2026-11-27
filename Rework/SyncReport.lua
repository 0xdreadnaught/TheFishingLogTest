-- Sync activity uses the journal's existing community theme.
local _, MF = ...
local ns = MF.Rework
local W = ns.W
local window, current, revision, state, reportCount
local Refresh

local function Reports()
    local reports = {}
    local active = MF:ActiveSyncReport()
    if active then reports[#reports+1] = active end
    for _, report in ipairs(MF:SyncHistory()) do reports[#reports+1] = report end
    return reports
end

local function Position(reports)
    for i, report in ipairs(reports) do if report == current then return i end end
end

local function Move(offset)
    local reports = Reports()
    local index = Position(reports)
    if index and reports[index+offset] then
        current = reports[index+offset]
        Refresh(false)
    end
end

local function MakeRow(kind, parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row.title = W:Label(row, kind == "header" and "GameFontNormal" or "GameFontHighlight", "")
    row.title:SetPoint("TOPLEFT", 4, -5)
    row.title:SetWordWrap(false)
    row.note = W:Label(row, "GameFontHighlightSmall", "", W.DIM)
    row.note:SetWordWrap(false)
    if kind == "header" then
        row.title:SetPoint("TOPRIGHT", -240, -5)
        row.note:SetPoint("TOPRIGHT", -4, -6)
        row.note:SetWidth(230)
        row.note:SetJustifyH("RIGHT")
        local line = row:CreateTexture(nil, "BACKGROUND")
        line:SetPoint("BOTTOMLEFT", 0, 2)
        line:SetPoint("BOTTOMRIGHT", 0, 2)
        line:SetHeight(1)
        line:SetColorTexture(0.65, 0.5, 0.18, 0.45)
    else
        row.title:SetPoint("TOPRIGHT", -4, -5)
        row.note:SetPoint("TOPLEFT", 4, -23)
        row.note:SetPoint("TOPRIGHT", -4, -23)
    end
    W:Tip(row, function(f) return f.item and f.item.title end, function(f)
        local item = f.item
        if not item then return end
        return (item.note or "")..((item.tip and item.tip ~= "") and ("\n"..item.tip) or "")
    end)
    return row
end

local function Build()
    if window then return end
    window = W:Window("TheFishingLogSyncReport", "Sync report", 700, 480, ns.ICON)
    ns.SyncReport = window
    window:SetPoint("CENTER")
    window:SetScale(math.min(1, (UIParent:GetWidth()-24)/700, (UIParent:GetHeight()-24)/480))
    local ground = W:Ground(window)
    ground:SetPoint("TOPLEFT", 4, -60)
    ground:SetPoint("BOTTOMRIGHT", -4, 4)
    W:HideTopCorners(ground)
    window.list = W:VList(window, MakeRow, function(row, item)
        row.title:SetText(item.title)
        row.note:SetText(item.note)
    end)
    window.list:SetPoint("TOPLEFT", 20, -76)
    window.list:SetPoint("BOTTOMRIGHT", -36, 76)
    window.hint = W:Label(window, "GameFontHighlightSmall", "Ends after 20s quiet. Received includes unchanged data; sends unconfirmed.", W.DIM)
    window.hint:SetPoint("BOTTOMLEFT", 20, 52)
    window.older = W:Button(window, "Older", 76, 24, function() Move(1) end)
    window.older:SetPoint("BOTTOMLEFT", 20, 18)
    window.newer = W:Button(window, "Newer", 76, 24, function() Move(-1) end)
    window.newer:SetPoint("LEFT", window.older, "RIGHT", 6, 0)
    window.page = W:Label(window, "GameFontHighlightSmall", "")
    window.page:SetPoint("LEFT", window.newer, "RIGHT", 12, 0)
    window.copy = W:Button(window, "Copy", 76, 24, function()
        MF:ShowCopyText("Sync report", MF:SyncReportText(current))
    end)
    window.copy:SetPoint("BOTTOMRIGHT", -20, 18)
    window.realm = W:Button(window, "Realm", 76, 24, function() MF:OpenJournal("realm") end)
    window.realm:SetPoint("RIGHT", window.copy, "LEFT", -6, 0)
end

Refresh = function(keep)
    if not window then return end
    revision, state = current and current.revision, current and current.state
    window.heading:SetText(state or "No activity")
    window.subheading:SetText(current and (date("%d %b %H:%M", current.at).." · "..#current.order.." exchanges") or "")
    window.list:SetItems(MF:SyncReportRows(current), keep)
    local reports = Reports()
    reportCount = #reports
    local index = Position(reports)
    window.page:SetText(index and (index.." / "..#reports) or "")
    window.older:SetEnabled(index ~= nil and index < #reports)
    window.newer:SetEnabled(index ~= nil and index > 1)
    window.copy:SetEnabled(current ~= nil)
end

function MF:OpenSyncReport(report)
    Build()
    current = report or self:ActiveSyncReport() or self:SyncHistory()[1]
    Refresh(false)
    window:Show()
end

MF:On("TFL_SYNC_REPORT_UPDATED", function(_, report)
    if not window or not window:IsShown() then return end
    if not current then current = report end
    if #Reports() ~= reportCount or (current == report and (revision ~= report.revision or state ~= report.state)) then Refresh(true) end
end)
