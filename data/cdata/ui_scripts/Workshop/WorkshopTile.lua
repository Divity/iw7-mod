local tileWidth = 300
local tileHeight = 241
local imageHeight = 169

local accentColor = 14032924

local typeBadges = {
    map = {text = "MAP", color = 3112920, width = 50},
    mod = {text = "MOD", color = 9323693, width = 50}
}

local soonBadge = {text = "COMING SOON", color = 14715422, width = 110}
local mutedColor = 10132122

local stateBadges = {
    installed = "^2INSTALLED",
    update = "^3UPDATE"
}

workshopReadyPreviews = workshopReadyPreviews or {}

local function updateTile(tile)
    local dataSource = tile:GetDataSource()
    if not dataSource or not dataSource.item then
        return
    end

    local item = dataSource.item
    tile.Title:setText(ToUpperCase(item.name), 0)

    local typeBadge = item.state == "soon" and soonBadge or typeBadges[item.type] or typeBadges.map
    tile.Type:setText(typeBadge.text, 0)
    tile.TypeBackground:SetRGBFromInt(typeBadge.color, 0)
    tile.TypeBackground:SetLeft(_1080p * -(typeBadge.width + 12), 0)
    tile.Type:SetLeft(_1080p * -(typeBadge.width + 12), 0)
    tile.Title:SetRight(_1080p * -(typeBadge.width + 22), 0)

    tile.Author:setText(item.author ~= "" and ToUpperCase("by " .. item.author) or "", 0)
    tile.Summary:setText(item.description, 0)

    local badge = stateBadges[item.state]
    if badge then
        tile.Badge:setText(badge, 0)
        tile.BadgeBackground:SetAlpha(0.8, 0)
    else
        tile.Badge:setText("", 0)
        tile.BadgeBackground:SetAlpha(0, 0)
    end

    if workshopReadyPreviews[item.id] then
        tile.Preview:setImage(RegisterMaterial("workshop_" .. item.id), 0)
        tile.Preview:SetRGBFromInt(16777215, 0)
        tile.Preview:SetAlpha(1, 0)
    else
        tile.Preview:SetAlpha(0, 0)
    end
end

local function PostLoadFunc(tile, controllerIndex, controller)
    assert(tile.GenericButton)

    tile.GenericButton:addEventHandler("button_action", function(clickedElement, eventArgs)
        local dataSource = tile:GetDataSource()
        dataSource.buttonOnClickFunction(clickedElement, eventArgs)
    end)

    tile.GenericButton:addEventHandler("button_over", function(hoveredElement, eventArgs)
        tile.Border:SetAlpha(1, 100)
        tile.TitleBar:SetRGBFromInt(16777215, 100)
        tile.Title:SetRGBFromInt(0, 100)
        tile.Author:SetRGBFromInt(accentColor, 100)
        tile.Summary:SetRGBFromInt(4210752, 100)
        local dataSource = tile:GetDataSource()
        dataSource.buttonOnHoverFunction(hoveredElement, eventArgs)
    end)

    tile.GenericButton:addEventHandler("button_up", function(unhoveredElement, eventArgs)
        tile.Border:SetAlpha(0, 100)
        tile.TitleBar:SetRGBFromInt(0, 100)
        tile.Title:SetRGBFromInt(14277081, 100)
        tile.Author:SetRGBFromInt(accentColor, 100)
        tile.Summary:SetRGBFromInt(mutedColor, 100)
    end)

    tile:registerEventHandler("grid_anim", function(element, event)
        element:SetAlpha(event.value)
    end)

    tile:registerEventHandler("workshop_preview", function(element, event)
        local dataSource = element:GetDataSource()
        if dataSource and dataSource.item and dataSource.item.id == event.id then
            updateTile(element)
        end
    end)

    tile:SubscribeToDataSourceThroughElement(tile, nil, function()
        updateTile(tile)
    end)
end

function WorkshopTile(menu, controller)
    local tile = LUI.UIButton.new()
    tile:SetAnchorsAndPosition(0, 1, 0, 1, 0, tileWidth * _1080p, 0, tileHeight * _1080p)
    tile.id = "WorkshopTile"

    local controllerIndex = controller and controller.controllerIndex
    if not controllerIndex and not Engine.InFrontend() then
        controllerIndex = tile:getRootController()
    end
    assert(controllerIndex)

    local Border = LUI.UIImage.new()
    Border.id = "Border"
    Border:SetRGBFromInt(accentColor, 0)
    Border:SetAlpha(0, 0)
    Border:SetAnchorsAndPosition(0, 0, 0, 0, _1080p * -3, _1080p * 3, _1080p * -3, _1080p * 3)
    tile:addElement(Border)
    tile.Border = Border

    local Background = LUI.UIImage.new()
    Background.id = "Background"
    Background:SetRGBFromInt(0, 0)
    Background:SetAlpha(0.6, 0)
    Background:SetAnchorsAndPosition(0, 0, 0, 0, 0, 0, 0, 0)
    tile:addElement(Background)
    tile.Background = Background

    local Preview = LUI.UIImage.new()
    Preview.id = "Preview"
    Preview:SetAlpha(0, 0)
    Preview:SetAnchorsAndPosition(0, 0, 0, 1, 0, 0, 0, _1080p * imageHeight)
    tile:addElement(Preview)
    tile.Preview = Preview

    local TitleBar = LUI.UIImage.new()
    TitleBar.id = "TitleBar"
    TitleBar:SetRGBFromInt(0, 0)
    TitleBar:SetAlpha(0.85, 0)
    TitleBar:SetAnchorsAndPosition(0, 0, 0, 0, 0, 0, _1080p * imageHeight, 0)
    tile:addElement(TitleBar)
    tile.TitleBar = TitleBar

    local Title = LUI.UIStyledText.new()
    Title.id = "Title"
    Title:SetRGBFromInt(14277081, 0)
    Title:SetFontSize(22 * _1080p)
    Title:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
    Title:SetAlignment(LUI.Alignment.Left)
    Title:SetStartupDelay(2000)
    Title:SetLineHoldTime(400)
    Title:SetAnimMoveTime(300)
    Title:SetEndDelay(1500)
    Title:SetCrossfadeTime(750)
    Title:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
    Title:SetMaxVisibleLines(1)
    Title:SetAnchorsAndPosition(0, 0, 0, 1, _1080p * 12, _1080p * -72, _1080p * 175, _1080p * 197)
    tile:addElement(Title)
    tile.Title = Title

    local TypeBackground = LUI.UIImage.new()
    TypeBackground.id = "TypeBackground"
    TypeBackground:SetRGBFromInt(3112920, 0)
    TypeBackground:SetAnchorsAndPosition(1, 0, 0, 1, _1080p * -62, _1080p * -12, _1080p * 177, _1080p * 196)
    tile:addElement(TypeBackground)
    tile.TypeBackground = TypeBackground

    local Type = LUI.UIText.new()
    Type.id = "Type"
    Type:setText("", 0)
    Type:SetRGBFromInt(16777215, 0)
    Type:SetFontSize(15 * _1080p)
    Type:SetFont(FONTS.GetFont(FONTS.MainBold.File))
    Type:SetAlignment(LUI.Alignment.Center)
    Type:SetAnchorsAndPosition(1, 0, 0, 1, _1080p * -62, _1080p * -12, _1080p * 179, _1080p * 194)
    tile:addElement(Type)
    tile.Type = Type

    local Author = LUI.UIText.new()
    Author.id = "Author"
    Author:setText("", 0)
    Author:SetRGBFromInt(accentColor, 0)
    Author:SetFontSize(16 * _1080p)
    Author:SetFont(FONTS.GetFont(FONTS.MainBold.File))
    Author:SetAlignment(LUI.Alignment.Left)
    Author:SetAnchorsAndPosition(0, 0, 0, 1, _1080p * 12, _1080p * -12, _1080p * 199, _1080p * 215)
    tile:addElement(Author)
    tile.Author = Author

    local Summary = LUI.UIStyledText.new()
    Summary.id = "Summary"
    Summary:setText("", 0)
    Summary:SetRGBFromInt(mutedColor, 0)
    Summary:SetFontSize(16 * _1080p)
    Summary:SetFont(FONTS.GetFont(FONTS.MainCondensed.File))
    Summary:SetAlignment(LUI.Alignment.Left)
    Summary:SetStartupDelay(2000)
    Summary:SetLineHoldTime(400)
    Summary:SetAnimMoveTime(300)
    Summary:SetEndDelay(1500)
    Summary:SetCrossfadeTime(750)
    Summary:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
    Summary:SetMaxVisibleLines(1)
    Summary:SetAnchorsAndPosition(0, 0, 0, 1, _1080p * 12, _1080p * -12, _1080p * 218, _1080p * 234)
    tile:addElement(Summary)
    tile.Summary = Summary

    local BadgeBackground = LUI.UIImage.new()
    BadgeBackground.id = "BadgeBackground"
    BadgeBackground:SetRGBFromInt(0, 0)
    BadgeBackground:SetAlpha(0, 0)
    BadgeBackground:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 8, _1080p * 128, _1080p * 8, _1080p * 32)
    tile:addElement(BadgeBackground)
    tile.BadgeBackground = BadgeBackground

    local Badge = LUI.UIText.new()
    Badge.id = "Badge"
    Badge:setText("", 0)
    Badge:SetFontSize(18 * _1080p)
    Badge:SetFont(FONTS.GetFont(FONTS.MainBold.File))
    Badge:SetAlignment(LUI.Alignment.Center)
    Badge:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 8, _1080p * 128, _1080p * 11, _1080p * 29)
    tile:addElement(Badge)
    tile.Badge = Badge

    local GenericButton = MenuBuilder.BuildRegisteredType("GenericButton", {
        controllerIndex = controllerIndex
    })
    GenericButton.id = "GenericButton"
    GenericButton:SetAlpha(0, 0)
    GenericButton:SetAnchorsAndPosition(0, 0, 0, 0, 0, 0, 0, 0)
    tile:addElement(GenericButton)
    tile.GenericButton = GenericButton

    PostLoadFunc(tile, controllerIndex, controller)
    return tile
end

MenuBuilder.registerType("WorkshopTile", WorkshopTile)
