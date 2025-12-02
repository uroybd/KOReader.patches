local UIManager = require("ui/uimanager")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local _ = require("gettext")
local util = require("util")
local ButtonDialog = require("ui/widget/buttondialog")
local BD = require("ui/bidi")
local C_ = _.pgettext
local ffiUtil = require("ffi/util")
local logger = require("logger")
local BlitBuffer = require("ffi/blitbuffer")
local Event = require("ui/event")

function ReaderHighlight:showHighlightDialog(index)
    local item = self.ui.annotation.annotations[index]
    local change_boundaries_enabled = not item.text_edited
    local start_prev, start_next, end_prev, end_next = "◁▒▒", "▷☓▒", "▒☓◁", "▒▒▷"
    if BD.mirroredUILayout() then
        -- BiDi will mirror the arrows, and this just works
        start_prev, start_next = start_next, start_prev
        end_prev, end_next = end_next, end_prev
    end
    local move_by_char = false
    local edit_highlight_dialog
    local buttons = {
        {
            {
                text = "\u{F48E}", -- Trash can (icon to prevent confusion of Delete/Details buttons)
                callback = function()
                    self:deleteHighlight(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = C_("Highlight", "Style"),
                callback = function()
                    self:editHighlightStyle(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = C_("Highlight", "Color"),
                enabled = item.drawer ~= "invert",
                callback = function()
                    self:editHighlightColor(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = _("Note"),
                callback = function()
                    self:editNote(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = _("Details"),
                callback = function()
                    self.ui.bookmark:showBookmarkDetails(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
            {
                text = "…",
                callback = function()
                    self.selected_text = util.tableDeepCopy(item)
                    self:onShowHighlightMenu(index)
                    UIManager:close(edit_highlight_dialog)
                end,
            },
        },
        {
            {
                text = start_prev,
                enabled = change_boundaries_enabled,
                callback = function()
                    self:updateHighlight(index, 0, -1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    self:updateHighlight(index, 0, -1, true)
                end,
            },
            {
                text = start_next,
                enabled = change_boundaries_enabled,
                callback = function()
                    self:updateHighlight(index, 0, 1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    self:updateHighlight(index, 0, 1, true)
                end,
            },
            {
                text = end_prev,
                enabled = change_boundaries_enabled,
                callback = function()
                    self:updateHighlight(index, 1, -1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    self:updateHighlight(index, 1, -1, true)
                end,
            },
            {
                text = end_next,
                enabled = change_boundaries_enabled,
                callback = function()
                    self:updateHighlight(index, 1, 1, move_by_char)
                end,
                hold_callback = function()
                    move_by_char = not move_by_char
                    self:updateHighlight(index, 1, 1, true)
                end,
            },
        },
        
    }
    local default_color, curr_color, keep_shown_on_apply
    if item then -- called from ReaderHighlight:editHighlightColor()
        default_color = self.view.highlight.saved_color
        curr_color = item.color or default_color
        keep_shown_on_apply = true
    else
        default_color = G_reader_settings:readSetting("highlight_color") or self._fallback_color
        curr_color = self.view.highlight.saved_color
    end
    local color_buttons = {}
    for _, v in ipairs(self.highlight_colors) do
        table.insert(color_buttons, {
                icon = v[2],
                callback = function() -- set color for new highlights in this bo
                    local color = v[2]
                    self:writePdfAnnotation("delete", item)
        item.color = color
        if self.ui.paging then
            self:writePdfAnnotation("save", item)
            if item.note then
                self:writePdfAnnotation("content", item, item.note)
            end
        end
        UIManager:setDirty(self.dialog, "ui")
        self.ui:handleEvent(Event:new("AnnotationsModified", { item }))
                end
        })
    end
    table.insert(buttons, color_buttons)
    edit_highlight_dialog = ButtonDialog:new{
        name = "edit_highlight_dialog", -- for unit tests
        buttons = buttons,
        anchor = function()
            return self:_getDialogAnchor(edit_highlight_dialog, index)
        end,
    }
    UIManager:show(edit_highlight_dialog)
end


function ReaderHighlight:onShowHighlightMenu(index)
    if not self.selected_text then
        return
    end

    local highlight_buttons = {{}}

    local columns = 3
    for idx, fn_button in ffiUtil.orderedPairs(self._highlight_buttons) do
        local button = fn_button(self, index)
        if not button.show_in_highlight_dialog_func or button.show_in_highlight_dialog_func() then
            if #highlight_buttons[#highlight_buttons] >= columns then
                table.insert(highlight_buttons, {})
            end
            table.insert(highlight_buttons[#highlight_buttons], button)
            logger.dbg("ReaderHighlight", idx..": line "..#highlight_buttons..", col "..#highlight_buttons[#highlight_buttons])
        end
    end

    self.highlight_dialog = ButtonDialog:new{
        buttons = highlight_buttons,
        anchor = function()
            return self:_getDialogAnchor(self.highlight_dialog, index)
        end,
        tap_close_callback = function()
            if self.hold_pos then
                self:clear()
            end
        end,
    }
    -- NOTE: Disable merging for this update,
    --       or the buggy Sage kernel may alpha-blend it into the page (with a bogus alpha value, to boot)...
    UIManager:show(self.highlight_dialog, "[ui]")
end
