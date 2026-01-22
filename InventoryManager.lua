local Util = require("frontiers_forge.util")
local Inventory  = require("frontiers_forge.inventory")
local Bank = require("frontiers_forge.bank")
local Gems = require("frontiers_forge.gems")

if Util.IsInGame() == 0 then return end

-- Bank slot id -> label
local BANK_SLOT_LABEL = {
    [1]="Head",[2]="Robe",[3]="Earring",[4]="Neck",[5]="Torso",
    [6]="Bracelet",[7]="2 Forearm",[8]="Ring",[9]="Waist",[10]="Legs",
    [11]="Boots",[12]="Weapon",[13]="Shield",[14]="Weapon",[15]="Weapon",
    [16]="Weapon",[17]="Weapon",[18]="Weapon",[19]="Gloves",
}

-- Rarity color coding:
-- Green for common, blue for uncommon, purple for rare, orange for ultra rare
local RARITY_COLOR = {
    ["Common"]     = { 0.2, 1.0, 0.2, 1.0 },
    ["Uncommon"]   = { 0.3, 0.6, 1.0, 1.0 },
    ["Rare"]       = { 0.7, 0.4, 1.0, 1.0 },
    ["Ultra Rare"] = { 1.0, 0.6, 0.2, 1.0 },
}

local function is_empty_name(name)
    return (not name) or name == "" or name == "(unnamed)" or name == "(unnamed item)"
end

local function fmt_name_amt(name, amt)
    if amt and amt > 1 then
        return ("%s (%d)"):format(name, amt)
    end
    return name
end

local function eq_display(name, amt, level, slot_label)
    return ("%s (Level %d) - %s")
        :format(fmt_name_amt(name, amt), level or 0, slot_label or "")
end

local function sort_ci(a, b)
    return string.lower(a) < string.lower(b)
end

local function bank_is_gear(it)
    local sid = it.slot or 0
    return sid >= 1 and sid <= 19
end

local function inv_is_equippable_slot(slot_id)
    return slot_id and slot_id >= 1 and slot_id <= 19
end

local function build_gem_entry(name, amt)
    local g = Gems.Get(name)
    if not g then return nil end
    local text = ("%s - %s - %s"):format(
        fmt_name_amt(name, amt),
        g.stat or "",
        g.type or ""
    )
    return { text = text, rarity = g.rarity or "" }
end

-- =========================
-- Cached state (only rebuild on refresh)
-- =========================
local state = state or {}
state.built = state.built or false
state.last_refresh = state.last_refresh or ""
state.inv_used = state.inv_used or 0
state.bank_used = state.bank_used or 0

state.inv_equipped = state.inv_equipped or {}
state.inv_gems = state.inv_gems or {}
state.inv_other_gear = state.inv_other_gear or {}
state.inv_other_plain = state.inv_other_plain or {}

state.bank_gear = state.bank_gear or {}
state.bank_gems = state.bank_gems or {}
state.bank_other = state.bank_other or {}

local function now_string()
    -- os.date is usually available; if not, we’ll just show blank.
    if os and os.date then
        return os.date("%Y-%m-%d %H:%M:%S")
    end
    return ""
end

local function clamp_used(n)
    n = n or 0
    if n < 0 then n = 0 end
    if n > 40 then n = 40 end
    return n
end

local function rebuild()
    -- reset lists
    state.inv_equipped = {}
    state.inv_gems = {}
    state.inv_other_gear = {}
    state.inv_other_plain = {}
    state.bank_gear = {}
    state.bank_gems = {}
    state.bank_other = {}

    -- counts
    local inv_used = Inventory.SlotsUsed and Inventory.SlotsUsed() or 0
    state.inv_used = clamp_used(inv_used)

    local bank_used = Bank.SlotsUsed and Bank.SlotsUsed() or 0
    state.bank_used = clamp_used(bank_used)

    -- inventory items via API
    local inv_items = Inventory.GetItems and Inventory.GetItems() or {}
    for _, it in ipairs(inv_items) do
        local name = it.name or ""
        local amt  = it.amount or 0

        if not is_empty_name(name) then
            local slot_id = it.slot or 0
            local level   = it.level_req or it.level or 0
            local equipped = false

            -- Prefer API field if present; fall back to status string if that’s what you expose.
            if it.equipped ~= nil then
                equipped = (it.equipped == true)
            elseif it.equipped_status then
                equipped = (it.equipped_status == "Equipped")
            end

            if equipped then
                local slot_label, order_key = Inventory.GetSlotLabelAndOrder(slot_id)
                table.insert(state.inv_equipped, {
                    text  = eq_display(name, amt, level, slot_label),
                    order = order_key,
                    slot  = slot_label,
                    idx   = it.idx or 0,
                })

            elseif Gems.IsGem(name) then
                local entry = build_gem_entry(name, amt)
                if entry then table.insert(state.inv_gems, entry) end

            else
                if inv_is_equippable_slot(slot_id) then
                    local slot_label, order_key = Inventory.GetSlotLabelAndOrder(slot_id)
                    table.insert(state.inv_other_gear, {
                        text  = eq_display(name, amt, level, slot_label),
                        order = order_key,
                        slot  = slot_label,
                        idx   = it.idx or 0,
                    })
                else
                    table.insert(state.inv_other_plain, fmt_name_amt(name, amt))
                end
            end
        end
    end

    -- Sort inventory equipped
    table.sort(state.inv_equipped, function(a,b)
        if a.order ~= b.order then return a.order < b.order end
        if a.slot ~= b.slot then return a.slot < b.slot end
        return (a.idx or 0) < (b.idx or 0)
    end)

    -- Sort inventory other-gear
    table.sort(state.inv_other_gear, function(a,b)
        if a.order ~= b.order then return a.order < b.order end
        if a.slot ~= b.slot then return a.slot < b.slot end
        return (a.idx or 0) < (b.idx or 0)
    end)

    -- Sort inventory gems + other plain
    table.sort(state.inv_gems, function(a,b) return string.lower(a.text) < string.lower(b.text) end)
    table.sort(state.inv_other_plain, sort_ci)

    -- bank items via API
    for _, it in ipairs(Bank.GetItems() or {}) do
        local name, amt = it.name or "", it.amount or 0
        if not is_empty_name(name) then
            if bank_is_gear(it) then
                local sid = it.slot or 0
                local label = BANK_SLOT_LABEL[sid] or tostring(sid)

                table.insert(state.bank_gear, {
                    text = eq_display(name, amt, it.level or 0, label),
                    slot = sid,
                    name = name,
                })
            elseif Gems.IsGem(name) then
                local entry = build_gem_entry(name, amt)
                if entry then table.insert(state.bank_gems, entry) end
            else
                table.insert(state.bank_other, fmt_name_amt(name, amt))
            end
        end
    end

    table.sort(state.bank_gear, function(a,b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        return string.lower(a.name) < string.lower(b.name)
    end)

    table.sort(state.bank_gems, function(a,b) return string.lower(a.text) < string.lower(b.text) end)
    table.sort(state.bank_other, sort_ci)

    state.last_refresh = now_string()
    state.built = true
end

-- =========================
-- UI helpers
-- =========================
local function render_list_numbered(list, start_index)
    local n = start_index or 1
    for _, v in ipairs(list) do
        ImGui.Text(("%d. %s"):format(n, v))
        n = n + 1
    end
    ImGui.Spacing()
    return n
end

local function render_rows_numbered(rows, start_index)
    local n = start_index or 1
    for _, r in ipairs(rows) do
        ImGui.Text(("%d. %s"):format(n, r.text))
        n = n + 1
    end
    ImGui.Spacing()
    return n
end

local function render_gem_list(gem_rows)
    for i, row in ipairs(gem_rows) do
        local rarity = row.rarity or ""
        local color = RARITY_COLOR[rarity]

        if color then
            ImGui.TextColored(color[1], color[2], color[3], color[4],
                ("%d. %s"):format(i, row.text))
        else
            ImGui.Text(("%d. %s"):format(i, row.text))
        end
    end
    ImGui.Spacing()
end

-- =========================
-- UI
-- =========================
ImGui.SetNextWindowSize(900, 780)
if ImGui.Begin("Inventory Manager") then
    -- Build once, then only on Refresh button
    if not state.built then
        rebuild()
    end

    if ImGui.Button("Refresh") then
        rebuild()
    end
    ImGui.SameLine()
    if state.last_refresh ~= "" then
        ImGui.Text(("Last refreshed: %s"):format(state.last_refresh))
    else
        ImGui.Text("Last refreshed: (unknown)")
    end

    ImGui.Separator()
    ImGui.Text(("Inventory Slots Used: %d / 40"):format(state.inv_used))
    ImGui.Text(("Bank Slots Used: %d / 40"):format(state.bank_used))
    ImGui.Separator()

    if ImGui.CollapsingHeader("Inventory - Equipped Gear") then
        if #state.inv_equipped == 0 then
            ImGui.Text("None")
        else
            render_rows_numbered(state.inv_equipped, 1)
        end
    end

    if ImGui.CollapsingHeader("Inventory - Gems") then
        if #state.inv_gems == 0 then
            ImGui.Text("None")
        else
            render_gem_list(state.inv_gems)
        end
    end

    if ImGui.CollapsingHeader("Inventory - Other Items") then
        if #state.inv_other_gear == 0 and #state.inv_other_plain == 0 then
            ImGui.Text("None")
        else
            local n = 1
            if #state.inv_other_gear > 0 then
                n = render_rows_numbered(state.inv_other_gear, n)
            end
            if #state.inv_other_plain > 0 then
                n = render_list_numbered(state.inv_other_plain, n)
            end
        end
    end

    ImGui.Separator()

    if ImGui.CollapsingHeader("Bank - Gear") then
        if #state.bank_gear == 0 then
            ImGui.Text("None")
        else
            render_rows_numbered(state.bank_gear, 1)
        end
    end

    if ImGui.CollapsingHeader("Bank - Gems") then
        if #state.bank_gems == 0 then
            ImGui.Text("None")
        else
            render_gem_list(state.bank_gems)
        end
    end

    if ImGui.CollapsingHeader("Bank - Other Items") then
        if #state.bank_other == 0 then
            ImGui.Text("None")
        else
            render_list_numbered(state.bank_other, 1)
        end
    end
end
ImGui.End()
