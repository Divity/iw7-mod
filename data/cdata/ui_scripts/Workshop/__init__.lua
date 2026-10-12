if not Engine.InFrontend() then
    return
end

require("WorkshopTile")
require("WorkshopMenu")

local buttonSpacing = 40 * _1080p

local function shift(element)
    if element then
        local left, top, right, bottom = element:getLocalRect()
        element:SetTop(top + buttonSpacing, 0)
        element:SetBottom(bottom + buttonSpacing, 0)
    end
end

local function addWorkshopButton(container, controllerIndex, before, below)
    local WorkshopButton = MenuBuilder.BuildRegisteredType("MenuButton", {
        controllerIndex = controllerIndex
    })
    WorkshopButton.id = "WorkshopButton"
    WorkshopButton.buttonDescription = "Browse and install community maps and mods."
    WorkshopButton.Text:setText(ToUpperCase("Workshop"), 0)
    WorkshopButton:addEventHandler("button_action", function(element, event)
        LUI.FlowManager.RequestAddMenu("WorkshopMenu", true, event.controller, false)
    end)

    local left, top, right, bottom = container.ModsButton:getLocalRect()
    WorkshopButton:SetAnchorsAndPosition(0, 1, 0, 1, left, right, top + buttonSpacing, bottom + buttonSpacing)

    if before then
        LUI.UIElement.addElementBefore(WorkshopButton, before)
    else
        container:addElement(WorkshopButton)
    end
    container.WorkshopButton = WorkshopButton

    for _, element in pairs(below) do
        shift(element)
    end

    local cLeft, cTop, cRight, cBottom = container:getLocalRect()
    container:SetBottom(cBottom + buttonSpacing, 0)
end

local function wrap(typeName, build)
    local original = MenuBuilder.m_types[typeName]
    if not original then
        return
    end

    MenuBuilder.m_types[typeName] = function(menu, controller)
        local self = original(menu, controller)
        local controllerIndex = controller and controller.controllerIndex
        if not controllerIndex and not Engine.InFrontend() then
            controllerIndex = self:getRootController()
        end
        if self.ModsButton then
            build(self, controllerIndex)
        end
        return self
    end
end

wrap("CPMainMenuButtons", function(self, controllerIndex)
    addWorkshopButton(self, controllerIndex, self.ContractsButton, {self.ContractsButton, self.ButtonDescription})
end)

wrap("MPMainMenuButtons", function(self, controllerIndex)
    addWorkshopButton(self, controllerIndex, self.StoreButton, {self.StoreButton})
end)

wrap("CampaignMenuButtons", function(self, controllerIndex)
    addWorkshopButton(self, controllerIndex, self.ButtonDescription, {self.ButtonDescription})
end)
