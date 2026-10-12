local workshopPath = "frontEnd.Workshop"

local accentColor = 14032924
local mutedColor = 10132122

local stateTexts = {
    none = "NOT INSTALLED",
    installed = "^2INSTALLED",
    update = "^3UPDATE AVAILABLE",
    soon = "^3COMING SOON"
}

local actionTexts = {
    none = "SELECT TO INSTALL",
    installed = "",
    update = "SELECT TO UPDATE",
    soon = ""
}

workshopPathCleanup = function()
    WipeGlobalModelsAtPath(workshopPath)
end

workshopReadyPreviews = workshopReadyPreviews or {}

local function formatSize(size)
    if size >= 1024 * 1024 * 1024 then
        return string.format("%.2f GB", size / (1024 * 1024 * 1024))
    end
    return string.format("%.1f MB", size / (1024 * 1024))
end

local function getItemMeta(item)
    if item.state == "soon" then
        return ToUpperCase(item.type)
    end

    local meta = ToUpperCase(item.type) .. "  /  " .. formatSize(item.size)
    if item.version ~= "" then
        meta = meta .. "  /  V" .. item.version
    end
    return meta
end

local function addText(parent, id, fontSize, font, left, right, top, bottom, color)
    local text = LUI.UIText.new()
    text.id = id
    text:setText("", 0)
    text:SetFontSize(fontSize * _1080p)
    text:SetFont(FONTS.GetFont(font.File))
    text:SetAlignment(LUI.Alignment.Left)
    text:SetRGBFromInt(color, 0)
    text:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * left, _1080p * right, _1080p * top, _1080p * bottom)
    parent:addElement(text)
    parent[id] = text
    return text
end

local function addImage(parent, id, color, alpha, left, right, top, bottom)
    local image = LUI.UIImage.new()
    image.id = id
    image:SetRGBFromInt(color, 0)
    image:SetAlpha(alpha, 0)
    image:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * left, _1080p * right, _1080p * top, _1080p * bottom)
    parent:addElement(image)
    parent[id] = image
    return image
end

local function updateItemImage(panel, item)
    if item and workshopReadyPreviews[item.id] then
        panel.Image:setImage(RegisterMaterial("workshop_" .. item.id), 0)
        panel.Image:SetRGBFromInt(16777215, 0)
        panel.Image:SetAlpha(1, 0)
    else
        panel.Image:SetAlpha(0, 0)
    end
end

local function updateInfoPanel(panel, item)
    if not item then
        panel:SetAlpha(0, 0)
        return
    end

    panel:SetAlpha(1, 150)
    panel.Title:setText(ToUpperCase(item.name), 0)
    panel.Author:setText(item.author ~= "" and ToUpperCase("by " .. item.author) or "", 0)
    panel.Meta:setText(getItemMeta(item), 0)
    panel.State:setText(stateTexts[item.state] or "", 0)
    panel.Description:setText(item.description, 0)
    local action = actionTexts[item.state] or ""
    panel.Action:setText(action, 0)
    panel.ActionBar:SetAlpha(action ~= "" and 0.9 or 0, 0)
    updateItemImage(panel, item)
end

local leaveMenu = function(menuElement, controllerIndex)
    LUI.FlowManager.RequestLeaveMenu(menuElement)
end

local updateItemSelection = function(menuElement, controllerIndex, item)
    local scopedData = LUI.FlowManager.GetScopedData(menuElement)
    scopedData.currentItem = item

    menuElement:processEvent({
        name = "menu_refresh"
    })
    local currentMenu = menuElement:GetCurrentMenu()
    assert(currentMenu.InfoPanel)
    updateInfoPanel(currentMenu.InfoPanel, item)
    Engine.PlaySound(CoD.SFX.SPMinimap)
end

local installItem = function(buttonElement, controllerIndex, item)
    if item.state ~= "installed" then
        workshop.install(item.id)
    end
end

local uninstallItem = function(menuElement, controllerIndex)
    local scopedData = LUI.FlowManager.GetScopedData(menuElement)
    local item = scopedData.currentItem
    if item and item.state ~= "none" then
        workshop.uninstall(item.id)
    end
end

local refreshItems = function(menuElement, controllerIndex)
    menuElement.StatusText:setText("Loading workshop...")
    workshop.refresh()
end

local populateItemList = function(menuElement, controllerIndex)
    local items = workshop.getitems()
    local itemList = {}
    for i = 1, #items do
        local item = items[i]
        if item.preview ~= "" then
            workshopReadyPreviews[item.id] = true
        end
        itemList[#itemList + 1] = {
            buttonLabel = ToUpperCase(item.name),
            item = item
        }
    end

    local dataSource = LUI.DataSourceFromList.new(#itemList)
    dataSource.MakeDataSourceAtIndex = function(dataSource, index, controllerIndex)
        return {
            buttonLabel = LUI.DataSourceInGlobalModel.new(workshopPath .. ".items." .. index,
                itemList[index + 1].buttonLabel),
            item = itemList[index + 1].item,
            buttonOnClickFunction = function(buttonElement, controllerIndex)
                installItem(buttonElement, controllerIndex, itemList[index + 1].item)
            end,
            buttonOnHoverFunction = function(buttonElement, controllerIndex)
                updateItemSelection(buttonElement, controllerIndex, itemList[index + 1].item)
            end,
        }
    end

    assert(menuElement.ItemSelectionList)
    menuElement.ItemSelectionList:SetGridDataSource(dataSource, controllerIndex)

    if #itemList == 0 then
        updateInfoPanel(menuElement.InfoPanel, nil)
    end
end

local function postLoadFunction(menuElement, controllerIndex, controller)
    assert(menuElement.bindButton)
    menuElement.bindButton:addEventHandler("button_secondary", leaveMenu)
    menuElement.bindButton:addEventHandler("button_alt1", uninstallItem)
    menuElement.bindButton:addEventHandler("button_alt2", refreshItems)

    menuElement:registerEventHandler("workshop_refreshed", function(element, event)
        if event.error ~= "" then
            element.StatusText:setText("^1" .. event.error)
        else
            element.StatusText:setText("")
        end
        populateItemList(element, controllerIndex)
    end)

    menuElement:registerEventHandler("workshop_preview", function(element, event)
        workshopReadyPreviews[event.id] = true
        local scopedData = LUI.FlowManager.GetScopedData(element)
        if scopedData.currentItem and scopedData.currentItem.id == event.id then
            updateItemImage(element.InfoPanel, scopedData.currentItem)
        end
    end)

    updateInfoPanel(menuElement.InfoPanel, nil)
    populateItemList(menuElement, controllerIndex)
    refreshItems(menuElement, controllerIndex)

    menuElement:addEventHandler("gain_focus", function(focusElement, controllerIndex)
        local itemSelectionList = focusElement.ItemSelectionList

        if itemSelectionList:getNumChildren() == 0 then
            return
        end

        local contentOffset = itemSelectionList:GetContentOffset(LUI.DIRECTION.vertical)
        itemSelectionList:SetFocusedPosition({
            x = 0,
            y = contentOffset
        }, true)
        local focusedElement = itemSelectionList:GetElementAtPosition(0, contentOffset)
        if focusedElement then
            focusedElement:processEvent({
                name = "gain_focus",
                controllerIndex = controllerIndex
            })
        end
    end)
end

local function buildInfoPanel(menuElement)
    local panel = LUI.UIElement.new()
    panel.id = "InfoPanel"
    panel:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 1234, _1080p * 1844, _1080p * 196, _1080p * 946)
    menuElement:addElement(panel)
    menuElement.InfoPanel = panel

    addImage(panel, "Background", 0, 0.55, 0, 610, 0, 750)
    addImage(panel, "Accent", accentColor, 1, 0, 610, 0, 4)
    addImage(panel, "Frame", 16777215, 0.15, 18, 592, 22, 347)
    addImage(panel, "ImageBackground", 0, 1, 20, 590, 24, 345)
    addImage(panel, "Image", 16777215, 0, 20, 590, 24, 345)

    local title = LUI.UIStyledText.new()
    title.id = "Title"
    title:setText("", 0)
    title:SetFontSize(38 * _1080p)
    title:SetFont(FONTS.GetFont(FONTS.MainBold.File))
    title:SetAlignment(LUI.Alignment.Left)
    title:SetStartupDelay(2000)
    title:SetLineHoldTime(400)
    title:SetAnimMoveTime(300)
    title:SetEndDelay(1500)
    title:SetCrossfadeTime(750)
    title:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
    title:SetMaxVisibleLines(1)
    title:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 20, _1080p * 590, _1080p * 362, _1080p * 400)
    panel:addElement(title)
    panel.Title = title

    addText(panel, "Author", 20, FONTS.MainBold, 20, 590, 404, 424, accentColor)
    addText(panel, "Meta", 18, FONTS.MainMedium, 20, 590, 430, 448, mutedColor)
    addText(panel, "State", 18, FONTS.MainBold, 20, 590, 454, 472, 16777215)
    addImage(panel, "Divider", 16777215, 0.15, 20, 590, 486, 488)
    addText(panel, "Description", 20, FONTS.MainCondensed, 20, 590, 502, 522, 14277081)
    addImage(panel, "ActionBar", accentColor, 0.9, 0, 610, 706, 750)
    addText(panel, "Action", 22, FONTS.MainBold, 20, 590, 717, 739, 16777215)

    return panel
end

function WorkshopMenu(arg0, controller)
    local menuElement = LUI.UIElement.new()
    menuElement.id = "WorkshopMenu"

    local controllerIndex = controller and controller.controllerIndex
    if not controllerIndex and not Engine.InFrontend() then
        controllerIndex = menuElement:getRootController()
    end
    assert(controllerIndex)

    menuElement:playSound("menu_open")

    if Engine.IsSingleplayer() then
        local backgroundImage = nil

        backgroundImage = LUI.UIImage.new()
        backgroundImage.id = "Background"
        backgroundImage:setImage(RegisterMaterial("sp_frontend_bink_background"), 0)
        menuElement:addElement(backgroundImage)
        menuElement.Background = backgroundImage

        local binkImage = nil

        binkImage = LUI.UIImage.new()
        binkImage.id = "Bink"
        binkImage:setImage(RegisterMaterial("cinematic"), 0)
        menuElement:addElement(binkImage)
        menuElement.Bink = binkImage
    end

    local buttonHelperBar = nil

    buttonHelperBar = MenuBuilder.BuildRegisteredType("ButtonHelperBar", {
        controllerIndex = controllerIndex
    })
    buttonHelperBar.id = "ButtonHelperBar"
    buttonHelperBar:SetAnchorsAndPosition(0, 0, 1, 0, 0, 0, _1080p * -85, 0)
    menuElement:addElement(buttonHelperBar)
    menuElement.ButtonHelperBar = buttonHelperBar

    local menuTitle = nil

    if Engine.IsAliensMode() then
        menuTitle = MenuBuilder.BuildRegisteredType("CPMenuTitle", {
            controllerIndex = controllerIndex
        })
    else
        menuTitle = MenuBuilder.BuildRegisteredType("MenuTitle", {
            controllerIndex = controllerIndex
        })
        menuTitle.MenuBreadcrumbs:setText(ToUpperCase(""), 0)
        menuTitle.Icon:SetTop(_1080p * -28.5, 0)
        menuTitle.Icon:SetBottom(_1080p * 61.5, 0)
    end
    menuTitle.id = "MenuTitle"
    menuTitle.MenuTitle:setText(ToUpperCase("Workshop"), 0)
    menuTitle:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 96, _1080p * 1056, _1080p * 54, _1080p * 134)
    menuElement:addElement(menuTitle)
    menuElement.MenuTitle = menuTitle

    buildInfoPanel(menuElement)

    local itemSelectionList = nil

    itemSelectionList = LUI.UIDataSourceGrid.new(nil, {
        maxVisibleColumns = 3,
        maxVisibleRows = 3,
        controllerIndex = controllerIndex,
        buildChild = function()
            return MenuBuilder.BuildRegisteredType("WorkshopTile", {
                controllerIndex = controllerIndex
            })
        end,
        wrapX = true,
        wrapY = true,
        spacingX = _1080p * 20,
        spacingY = _1080p * 20,
        columnWidth = _1080p * 300,
        rowHeight = _1080p * 241,
        scrollingThresholdX = 1,
        scrollingThresholdY = 1,
        adjustSizeToContent = false,
        horizontalAlignment = LUI.Alignment.Left,
        verticalAlignment = LUI.Alignment.Top,
        springCoefficient = 600,
        maxVelocity = 5000
    })
    itemSelectionList.id = "ItemSelectionList"
    itemSelectionList:setUseStencil(false)
    itemSelectionList:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 130, _1080p * 1070, _1080p * 216, _1080p * 979)
    menuElement:addElement(itemSelectionList)
    menuElement.ItemSelectionList = itemSelectionList

    local arrowUp = nil

    arrowUp = MenuBuilder.BuildRegisteredType("ArrowUp", {
        controllerIndex = controllerIndex
    })
    arrowUp.id = "ArrowUp"
    arrowUp:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 1050, _1080p * 1070, _1080p * 162, _1080p * 202)
    menuElement:addElement(arrowUp)
    menuElement.ArrowUp = arrowUp

    local arrowDown = nil

    arrowDown = MenuBuilder.BuildRegisteredType("ArrowDown", {
        controllerIndex = controllerIndex
    })
    arrowDown.id = "ArrowDown"
    arrowDown:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 930, _1080p * 950, _1080p * 162, _1080p * 202)
    menuElement:addElement(arrowDown)
    menuElement.ArrowDown = arrowDown

    local listCount = nil

    listCount = LUI.UIText.new()
    listCount.id = "ListCount"
    listCount:setText("", 0)
    listCount:SetFontSize(24 * _1080p)
    listCount:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
    listCount:SetAlignment(LUI.Alignment.Center)
    listCount:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 950, _1080p * 1050, _1080p * 170, _1080p * 194)
    menuElement:addElement(listCount)
    menuElement.ListCount = listCount

    local statusText = nil

    statusText = LUI.UIText.new()
    statusText.id = "StatusText"
    statusText:setText("", 0)
    statusText:SetFontSize(20 * _1080p)
    statusText:SetFont(FONTS.GetFont(FONTS.MainBold.File))
    statusText:SetAlignment(LUI.Alignment.Left)
    statusText:SetAnchorsAndPosition(0, 1, 0, 1, _1080p * 130, _1080p * 920, _1080p * 170, _1080p * 194)
    menuElement:addElement(statusText)
    menuElement.StatusText = statusText

    itemSelectionList:AddArrow(arrowUp)
    itemSelectionList:AddArrow(arrowDown)
    itemSelectionList:AddItemNumbers(listCount)

    menuElement.addButtonHelperFunction = function(arg0, arg1)
        arg0:AddButtonHelperText({
            helper_text = Engine.Localize("MENU_BACK"),
            button_ref = "button_secondary",
            side = "left",
            clickable = true
        })
        arg0:AddButtonHelperText({
            helper_text = "Uninstall",
            button_ref = "button_alt1",
            side = "left",
            clickable = true
        })
        arg0:AddButtonHelperText({
            helper_text = "Refresh",
            button_ref = "button_alt2",
            side = "left",
            clickable = true
        })
    end

    menuElement:addEventHandler("menu_create", menuElement.addButtonHelperFunction)

    local bindButton = LUI.UIBindButton.new()
    bindButton.id = "selfBindButton"
    menuElement:addElement(bindButton)
    menuElement.bindButton = bindButton

    postLoadFunction(menuElement, controllerIndex, controller)

    if Engine.InFrontend() then
        local Blur = LUI.UIElement.new({
            worldBlur = 5
        })
        Blur:setupWorldBlur()
        Blur.id = "blur"
        menuElement:addElement(Blur)
    end

    return menuElement
end

MenuBuilder.registerType("WorkshopMenu", WorkshopMenu)
LUI.FlowManager.RegisterStackPopBehaviour("WorkshopMenu", workshopPathCleanup)
