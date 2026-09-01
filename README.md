# amxmodx-navmesh

Projects used as references:
[ReGameDLL](https://github.com/rehlds/ReGameDLL_CS)
[sourcepawn-navmesh](https://github.com/Kenzzer/sourcepawn-navmesh)

# Requeriments:
- AmxModX 1.9 or above (Recommended)

# Important:
The system is solely for creating, saving, and retrieving navmesh data.
I'm not going to add native pathfinding for bots/NPCs; you can implement it yourselves and even submit a pull request.

## Bot path helpers (new)
- Cached A*: `Navmesh_BuildPathCached` + `Navmesh_ClearPathCache`
- Shared destination flow-fields: `Navmesh_BuildFlowField`, `Navmesh_GetPathFromFlowField`, `Navmesh_DestroyFlowField`, `Navmesh_IsFlowFieldValid`
- Group helper: `Navmesh_BuildGroupPathsToArea`
- Async queue: `Navmesh_RequestPath`, `Navmesh_CancelPathRequest`
- Path-follow state: `Navmesh_PathFollow_*`

### Cached single request
```pawn
new Array:path = ArrayCreate(NavPathSegment);
if (Navmesh_BuildPathCached(startArea, goalArea, path, NAV_ROUTE_FASTEST))
{
    // use path
}
ArrayDestroy(path);
```

### Shared flow-field for many bots
```pawn
new flow = Navmesh_BuildFlowField(goalArea, NAV_ROUTE_FASTEST);
if (flow)
{
    for (new i = 0; i < botCount; i++)
    {
        new Array:path = ArrayCreate(NavPathSegment);
        if (Navmesh_GetPathFromFlowField(flow, botAreas[i], path))
        {
            // use path for this bot
        }
        ArrayDestroy(path);
    }
    Navmesh_DestroyFlowField(flow);
}
```

### Async callback + path follow
```pawn
public RequestBotPath(bot, startArea, goalArea)
{
    Navmesh_RequestPath(startArea, goalArea, "OnBotPathReady", NAV_ROUTE_FASTEST);
}

public OnBotPathReady(requestId, bool:success, Array:path)
{
    if (success)
    {
        Navmesh_PathFollow_SetTarget(1, path); // player/bot index example
    }
    ArrayDestroy(path); // callback owns async path handle
}
```
