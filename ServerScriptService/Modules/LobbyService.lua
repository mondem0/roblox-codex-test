local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage.Modules.Config.LobbyConfig)

local DEFAULT_ROUNDS = {
    { Id = "Solo", RequiredPlayers = 1, DisplayName = "1 Player" },
    { Id = "Duo", RequiredPlayers = 2, DisplayName = "2 Players" },
    { Id = "Trio", RequiredPlayers = 3, DisplayName = "3 Players" },
    { Id = "Squad", RequiredPlayers = 4, DisplayName = "4 Players" },
}

local LobbyService = {}
LobbyService.__index = LobbyService

local function cloneRoundInfo(roundEntry)
    local copy = {}
    for key, value in pairs(roundEntry) do
        copy[key] = value
    end
    copy.Key = roundEntry.Key or roundEntry.Id or tostring(roundEntry.RequiredPlayers)
    return copy
end

local function sanitizeLoadout(loadout)
    local sanitized = {}
    local seen = {}

    if typeof(loadout) ~= "table" then
        return sanitized
    end

    for _, towerType in ipairs(loadout) do
        if typeof(towerType) == "string" and towerType ~= "" and not seen[towerType] then
            table.insert(sanitized, towerType)
            seen[towerType] = true
        end
    end

    return sanitized
end

function LobbyService.new(remotes)
    local self = setmetatable({}, LobbyService)

    self.Remotes = remotes or {}
    self.RoundTypes = {}
    self.WaitingRooms = {}
    self.PlayerLoadouts = {}
    self.PlayerRound = {}
    self.ActiveGroup = nil
    self.State = "lobby"
    self.MapOptions = nil
    self.MapVotes = {}
    self.MapPool = LobbyConfig.MapPool or {}
    self.OnGroupReady = nil

    local sourceRounds = LobbyConfig.RoundTypes or DEFAULT_ROUNDS
    for _, round in ipairs(sourceRounds) do
        local entry = cloneRoundInfo(round)
        entry.Key = entry.Key or entry.Id or tostring(entry.RequiredPlayers)
        entry.DisplayName = entry.DisplayName or string.format("%d Player%s", entry.RequiredPlayers, entry.RequiredPlayers == 1 and "" or "s")
        table.insert(self.RoundTypes, entry)
        self.WaitingRooms[entry.Key] = {
            Players = {},
            Ready = {},
            CountdownActive = false,
            CountdownRemaining = 0,
            CountdownTask = nil,
        }
    end

    Players.PlayerRemoving:Connect(function(player)
        self:OnPlayerRemoving(player)
    end)

    return self
end

function LobbyService:SetGroupReadyCallback(callback)
    self.OnGroupReady = callback
end

function LobbyService:SetPhase(phase)
    self.State = phase or "lobby"
    self:BroadcastLobbyState()
end

function LobbyService:GetLoadout(player)
    return self.PlayerLoadouts[player]
end

function LobbyService:SetLoadout(player, loadout)
    local sanitized = sanitizeLoadout(loadout)
    self.PlayerLoadouts[player] = sanitized
    self:BroadcastLobbyState()
end

function LobbyService:HasEligibleLoadout(player)
    local loadout = self.PlayerLoadouts[player]
    return loadout and #loadout > 0
end

function LobbyService:GetRoundEntry(roundKey)
    for _, entry in ipairs(self.RoundTypes) do
        if entry.Key == roundKey then
            return entry
        end
    end
    return nil
end

function LobbyService:GetWaitingRoom(roundKey)
    return self.WaitingRooms[roundKey]
end

local function removeFromArray(array, value)
    for index = #array, 1, -1 do
        if array[index] == value then
            table.remove(array, index)
        end
    end
end

function LobbyService:LeaveRound(player)
    local roundKey = self.PlayerRound[player]
    if not roundKey then
        return
    end

    local room = self:GetWaitingRoom(roundKey)
    if not room then
        self.PlayerRound[player] = nil
        self:BroadcastLobbyState()
        return
    end

    removeFromArray(room.Players, player)
    room.Ready[player] = nil
    self.PlayerRound[player] = nil

    if room.CountdownActive then
        if #room.Players ~= self:GetRoundEntry(roundKey).RequiredPlayers then
            self:CancelCountdown(roundKey)
        else
            local allReady = true
            for _, occupant in ipairs(room.Players) do
                if not room.Ready[occupant] then
                    allReady = false
                    break
                end
            end
            if not allReady then
                self:CancelCountdown(roundKey)
            end
        end
    end

    self:BroadcastLobbyState()
end

function LobbyService:JoinRound(player, roundKey)
    if self.State ~= "lobby" then
        return false, "Round already in progress"
    end

    local roundEntry = self:GetRoundEntry(roundKey)
    if not roundEntry then
        return false, "Round not found"
    end

    local room = self:GetWaitingRoom(roundKey)
    if not room then
        return false, "Waiting room unavailable"
    end

    if not self:HasEligibleLoadout(player) then
        return false, "Select at least one tower first"
    end

    if self.PlayerRound[player] and self.PlayerRound[player] ~= roundKey then
        self:LeaveRound(player)
    end

    for _, occupant in ipairs(room.Players) do
        if occupant == player then
            return true
        end
    end

    if #room.Players >= roundEntry.RequiredPlayers then
        return false, "Waiting room full"
    end

    table.insert(room.Players, player)
    room.Ready[player] = false
    self.PlayerRound[player] = roundKey
    self:BroadcastLobbyState()
    return true
end

function LobbyService:SetReady(player, ready)
    local roundKey = self.PlayerRound[player]
    if not roundKey then
        return
    end

    local room = self:GetWaitingRoom(roundKey)
    if not room then
        return
    end

    room.Ready[player] = ready and true or false

    if room.CountdownActive then
        if not ready then
            self:CancelCountdown(roundKey)
        end
        self:BroadcastLobbyState()
        return
    end

    local roundEntry = self:GetRoundEntry(roundKey)
    if #room.Players == roundEntry.RequiredPlayers then
        local allReady = true
        for _, occupant in ipairs(room.Players) do
            if not room.Ready[occupant] then
                allReady = false
                break
            end
        end

        if allReady then
            self:BeginCountdown(roundKey)
        end
    end

    self:BroadcastLobbyState()
end

function LobbyService:BeginCountdown(roundKey)
    local room = self:GetWaitingRoom(roundKey)
    if not room or room.CountdownActive then
        return
    end

    room.CountdownActive = true
    room.CountdownRemaining = 10

    room.CountdownTask = task.spawn(function()
        while room.CountdownActive and room.CountdownRemaining > 0 do
            self:BroadcastLobbyState()
            task.wait(1)
            room.CountdownRemaining -= 1
        end

        if room.CountdownActive and room.CountdownRemaining <= 0 then
            self:HandleCountdownFinished(roundKey)
        else
            self:BroadcastLobbyState()
        end
    end)
end

function LobbyService:CancelCountdown(roundKey)
    local room = self:GetWaitingRoom(roundKey)
    if not room then
        return
    end

    room.CountdownActive = false
    room.CountdownRemaining = 0
    room.CountdownTask = nil
    self:BroadcastLobbyState()
end

function LobbyService:HandleCountdownFinished(roundKey)
    local room = self:GetWaitingRoom(roundKey)
    if not room then
        return
    end

    local roundEntry = self:GetRoundEntry(roundKey)
    if #room.Players < roundEntry.RequiredPlayers then
        self:CancelCountdown(roundKey)
        return
    end

    local participants = {}
    for _, player in ipairs(room.Players) do
        table.insert(participants, player)
    end

    room.CountdownActive = false
    room.CountdownRemaining = 0
    room.CountdownTask = nil
    room.Players = {}
    room.Ready = {}

    for player, currentRound in pairs(self.PlayerRound) do
        if currentRound == roundKey then
            self.PlayerRound[player] = nil
        end
    end

    self.ActiveGroup = {
        RoundKey = roundKey,
        Participants = participants,
        RequiredPlayers = roundEntry.RequiredPlayers,
    }

    self:SetPhase("mapSelection")
    self:StartMapSelection()
end

function LobbyService:GetActiveParticipants()
    if not (self.ActiveGroup and self.ActiveGroup.Participants) then
        return {}
    end
    return self.ActiveGroup.Participants
end

function LobbyService:StartMapSelection()
    local participants = self:GetActiveParticipants()
    if #participants == 0 then
        self.ActiveGroup = nil
        self:SetPhase("lobby")
        return
    end

    local options = {}
    local shuffled = {}
    for index, entry in ipairs(self.MapPool) do
        table.insert(shuffled, {Index = index, Entry = entry})
    end

    if #shuffled == 0 then
        table.insert(shuffled, { Index = 1, Entry = { Name = "Default", ModelName = "Map" } })
    end

    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    local optionCount = math.min(3, #shuffled)
    for i = 1, optionCount do
        local record = shuffled[i]
        table.insert(options, {
            Name = record.Entry.Name or ("Map " .. tostring(record.Index)),
            ModelName = record.Entry.ModelName,
            Description = record.Entry.Description,
            SourceIndex = record.Index,
        })
    end

    if #options == 0 then
        table.insert(options, { Name = "Default", ModelName = "Map" })
    end

    self.MapOptions = options
    self.MapVotes = {}

    for _, player in ipairs(participants) do
        if self.Remotes.MapSelectionStarted then
            self.Remotes.MapSelectionStarted:FireClient(player, {
                Options = options,
                TotalPlayers = #participants,
            })
        end
    end

    self:BroadcastLobbyState()
end

function LobbyService:IsParticipant(player)
    local participants = self:GetActiveParticipants()
    for _, participant in ipairs(participants) do
        if participant == player then
            return true
        end
    end
    return false
end

function LobbyService:SubmitVote(player, optionIndex)
    if self.State ~= "mapSelection" then
        return
    end

    if not self:IsParticipant(player) then
        return
    end

    if not (self.MapOptions and self.MapOptions[optionIndex]) then
        return
    end

    self.MapVotes[player] = optionIndex

    local counts = {}
    for _, index in pairs(self.MapVotes) do
        counts[index] = (counts[index] or 0) + 1
    end

    local payload = {
        Counts = counts,
        TotalPlayers = #self:GetActiveParticipants(),
        PlayerVotes = {},
    }

    for votePlayer, index in pairs(self.MapVotes) do
        table.insert(payload.PlayerVotes, {
            UserId = votePlayer.UserId,
            Name = votePlayer.DisplayName or votePlayer.Name,
            Vote = index,
        })
    end

    for _, participant in ipairs(self:GetActiveParticipants()) do
        if self.Remotes.MapVoteUpdated then
            self.Remotes.MapVoteUpdated:FireClient(participant, payload)
        end
    end

    local voteCount = 0
    for _ in pairs(self.MapVotes) do
        voteCount += 1
    end

    if voteCount == #self:GetActiveParticipants() then
        self:FinalizeMapSelection()
    end
end

function LobbyService:FinalizeMapSelection()
    local participants = self:GetActiveParticipants()
    if #participants == 0 then
        self.ActiveGroup = nil
        self:SetPhase("lobby")
        return
    end

    if not self.MapOptions then
        return
    end

    local counts = {}
    for _, index in pairs(self.MapVotes) do
        counts[index] = (counts[index] or 0) + 1
    end

    local highest = 0
    local contenders = {}

    for optionIndex, _ in ipairs(self.MapOptions) do
        local votes = counts[optionIndex] or 0
        if votes > highest then
            highest = votes
            contenders = { optionIndex }
        elseif votes == highest then
            table.insert(contenders, optionIndex)
        end
    end

    if #contenders == 0 then
        table.insert(contenders, 1)
    end

    local selectedIndex = contenders[math.random(1, #contenders)]
    local selectedOption = self.MapOptions[selectedIndex]

    for _, participant in ipairs(participants) do
        if self.Remotes.MapSelectionFinalized then
            self.Remotes.MapSelectionFinalized:FireClient(participant, {
                SelectedIndex = selectedIndex,
                Option = selectedOption,
                Counts = counts,
            })
        end
    end

    if self.OnGroupReady then
        self.OnGroupReady({
            RoundKey = self.ActiveGroup and self.ActiveGroup.RoundKey,
            Participants = participants,
            SelectedOption = selectedOption,
        })
    end

    self:SetPhase("inRound")
    self.ActiveGroup.SelectedOption = selectedOption
    self:BroadcastLobbyState()
end

function LobbyService:OnPlayerRemoving(player)
    self.PlayerLoadouts[player] = nil

    if self.ActiveGroup and self:IsParticipant(player) then
        removeFromArray(self.ActiveGroup.Participants, player)
        self.MapVotes[player] = nil
        if #self.ActiveGroup.Participants == 0 then
            self.ActiveGroup = nil
            self:SetPhase("lobby")
        end
    end

    if self.PlayerRound[player] then
        self:LeaveRound(player)
    else
        self:BroadcastLobbyState()
    end
end

function LobbyService:BuildStateForPlayer(player)
    local rounds = {}
    for _, roundEntry in ipairs(self.RoundTypes) do
        local room = self:GetWaitingRoom(roundEntry.Key)
        local players = {}
        if room then
            for _, occupant in ipairs(room.Players) do
                table.insert(players, {
                    UserId = occupant.UserId,
                    Name = occupant.DisplayName or occupant.Name,
                    Ready = room.Ready[occupant] == true,
                })
            end
        end

        table.insert(rounds, {
            Key = roundEntry.Key,
            DisplayName = roundEntry.DisplayName,
            RequiredPlayers = roundEntry.RequiredPlayers,
            Description = roundEntry.Description,
            Players = players,
            Countdown = room and room.CountdownActive and room.CountdownRemaining or 0,
        })
    end

    local currentRound = self.PlayerRound[player]
    local currentReady = false
    if currentRound then
        local room = self:GetWaitingRoom(currentRound)
        if room then
            currentReady = room.Ready[player] == true
        end
    end

    local activeGroup
    if self.ActiveGroup and self.ActiveGroup.Participants then
        activeGroup = {
            RoundKey = self.ActiveGroup.RoundKey,
            Players = {},
        }
        for _, participant in ipairs(self.ActiveGroup.Participants) do
            table.insert(activeGroup.Players, {
                UserId = participant.UserId,
                Name = participant.DisplayName or participant.Name,
            })
        end
        if self.ActiveGroup.SelectedOption then
            activeGroup.SelectedOption = self.ActiveGroup.SelectedOption
        end
    end

    return {
        Phase = self.State,
        Rounds = rounds,
        Player = {
            HasLoadout = self:HasEligibleLoadout(player),
            CurrentRound = currentRound,
            Ready = currentReady,
        },
        ActiveGroup = activeGroup,
    }
end

function LobbyService:BroadcastLobbyState()
    if not self.Remotes.LobbyStateUpdated then
        return
    end

    for _, player in ipairs(Players:GetPlayers()) do
        local state = self:BuildStateForPlayer(player)
        self.Remotes.LobbyStateUpdated:FireClient(player, state)
    end
end

function LobbyService:CanUseTower(player, towerType)
    local loadout = self.PlayerLoadouts[player]
    if not loadout or #loadout == 0 then
        return true
    end

    for _, entry in ipairs(loadout) do
        if entry == towerType then
            return true
        end
    end

    return false
end

function LobbyService:IsActivePlayer(player)
    if not self.ActiveGroup or self.State ~= "inRound" then
        return false
    end

    return self:IsParticipant(player)
end

function LobbyService:RoundEnded()
    self.ActiveGroup = nil
    self.MapOptions = nil
    self.MapVotes = {}
    self:SetPhase("lobby")
end

return LobbyService
