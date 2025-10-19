local LobbyConfig = {}

LobbyConfig.RoundTypes = {
    {
        Id = "Solo",
        RequiredPlayers = 1,
        DisplayName = "1 Player",
        Description = "Play alone with a single player.",
    },
    {
        Id = "Duo",
        RequiredPlayers = 2,
        DisplayName = "2 Players",
        Description = "Team up with one other player.",
    },
    {
        Id = "Trio",
        RequiredPlayers = 3,
        DisplayName = "3 Players",
        Description = "Coordinate as a three-player squad.",
    },
    {
        Id = "Squad",
        RequiredPlayers = 4,
        DisplayName = "4 Players",
        Description = "Fill all four seats for the toughest rounds.",
    },
}

LobbyConfig.MapPool = {
    {
        Name = "Grasslands",
        ModelName = "Grasslands",
        Description = "A balanced map with long curves for splash towers.",
    },
    {
        Name = "CrystalCaverns",
        ModelName = "CrystalCaverns",
        Description = "Tight tunnels that reward slowing and area control.",
    },
    {
        Name = "SunsetPort",
        ModelName = "SunsetPort",
        Description = "Wide docks with branching paths for advanced pathfinding.",
    },
    {
        Name = "FrostRuins",
        ModelName = "FrostRuins",
        Description = "A snowy ruin with long straights perfect for snipers.",
    },
}

return LobbyConfig
