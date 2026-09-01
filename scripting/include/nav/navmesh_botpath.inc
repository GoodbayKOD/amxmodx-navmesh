#if defined _navmesh_botpath_included
    #endinput
#endif
#define _navmesh_botpath_included

#include <amxmodx>
#include <nav/navmesh_const>

/**
 * Cached path builder between two areas.
 */
native bool:Navmesh_BuildPathCached(startArea, goalArea, Array:pathOut, NavRouteType:routeType = NAV_ROUTE_FASTEST);

/**
 * Clears all cached paths.
 */
native Navmesh_ClearPathCache();

/**
 * Builds a flow-field handle for a goal area.
 */
native Navmesh_BuildFlowField(goalArea, NavRouteType:routeType = NAV_ROUTE_FASTEST);

/**
 * Builds a path using a previously built flow-field.
 */
native bool:Navmesh_GetPathFromFlowField(flowFieldId, startArea, Array:pathOut);

/**
 * Destroys a flow-field handle.
 */
native bool:Navmesh_DestroyFlowField(flowFieldId);

/**
 * Checks if a flow-field handle is valid for the current navmesh generation.
 */
native bool:Navmesh_IsFlowFieldValid(flowFieldId);

/**
 * Builds paths for multiple starts to one goal using a shared flow-field.
 *
 * @param goalArea       Goal area index
 * @param startAreas     Input area list (cell array)
 * @param startCount     Number of starts in startAreas
 * @param pathsOut       Output array of Array handles (one path per start)
 * @param statusOut      Output array of bool states per start
 * @param routeType      Route type
 * @return               Built flow-field id, 0 on failure
 */
native Navmesh_BuildGroupPathsToArea(goalArea, const startAreas[], startCount, Array:pathsOut, Array:statusOut, NavRouteType:routeType = NAV_ROUTE_FASTEST);

/**
 * Queues an async path request. Callback signature:
 * public MyPathCallback(requestId, bool:success, Array:path)
 */
native Navmesh_RequestPath(startArea, goalArea, const callbackName[], NavRouteType:routeType = NAV_ROUTE_FASTEST);

/**
 * Cancels a queued async path request.
 */
native bool:Navmesh_CancelPathRequest(requestId);

/**
 * Path-follow helper APIs per player index [1..32].
 */
native bool:Navmesh_PathFollow_SetTarget(player, Array:path);
native bool:Navmesh_PathFollow_GetTarget(player, &targetArea, &pathIndex, &pathLength);
native bool:Navmesh_PathFollow_Advance(player);
native bool:Navmesh_PathFollow_IsFinished(player);
native Navmesh_PathFollow_Reset(player);
native Navmesh_PathFollow_GetRemaining(player);

#if defined NAVMESH_BOTPATH_INTERNAL

forward bool:BuildPathAStar(iStartArea, iGoalArea, Array:aPathOut, NavRouteType:routeType);
forward bool:IsValidArea(iAreaIndex, bool:bDeleteCheck = true);
forward Array:GetAreaConnectArray(const sArea[NavArea], NavDirType:dir);
forward Float:Math_GetMoveCost(iFromArea, iToArea, NavRouteType:routeType);
forward NavDirType:GetDirectionFromTo(iFromArea, iToArea);
forward HeapPushArea(Array:aHeap, iArea, Float:fCost, Float:fHeuristic);
forward HeapPopArea(Array:aHeap, &Float:fCostOut);

const NAVMESH_BOTPATH_MAX_PLAYERS = 32;
const NAVMESH_BOTPATH_TASK_ID = 21941;
const NAVMESH_BOTPATH_FRAME_BUDGET = 2;
const Float:NAVMESH_BOTPATH_INFINITY = 99999999.0;

enum _:NavPathCacheEntry
{
    CACHE_START_AREA,
    CACHE_GOAL_AREA,
    NavRouteType:CACHE_ROUTE_TYPE,
    CACHE_GENERATION,
    Array:CACHE_PATH
};

enum _:NavFlowFieldEntry
{
    FLOW_GOAL_AREA,
    NavRouteType:FLOW_ROUTE_TYPE,
    FLOW_GENERATION,
    bool:FLOW_VALID,
    Array:FLOW_NEXT_HOP,
    Array:FLOW_DISTANCE
};

enum _:NavAsyncRequestEntry
{
    REQUEST_ID,
    REQUEST_START_AREA,
    REQUEST_GOAL_AREA,
    NavRouteType:REQUEST_ROUTE_TYPE,
    REQUEST_GENERATION,
    REQUEST_PLUGIN_ID,
    bool:REQUEST_CANCELLED,
    REQUEST_CALLBACK[64]
};

enum _:NavPathFollowState
{
    FOLLOW_TARGET_AREA,
    Array:FOLLOW_PATH,
    FOLLOW_PATH_INDEX,
    FOLLOW_PATH_LENGTH,
    FOLLOW_GENERATION
};

new g_iNavGeneration = 1;
new Trie:g_tPathCache = Invalid_Trie;
new Array:g_aPathCacheEntries = Invalid_Array;
new Array:g_aFlowFields = Invalid_Array;
new Array:g_aAsyncQueue = Invalid_Array;
new g_iNextAsyncRequestID = 1;
new bool:g_bAsyncQueueRunning;
new g_aPathFollowState[NAVMESH_BOTPATH_MAX_PLAYERS + 1][NavPathFollowState];

public NavmeshBotPath_RegisterNatives()
{
    register_native("Navmesh_BuildPathCached", "native_build_path_cached");
    register_native("Navmesh_ClearPathCache", "native_clear_path_cache");
    register_native("Navmesh_BuildFlowField", "native_build_flow_field");
    register_native("Navmesh_GetPathFromFlowField", "native_get_path_from_flow_field");
    register_native("Navmesh_DestroyFlowField", "native_destroy_flow_field");
    register_native("Navmesh_IsFlowFieldValid", "native_is_flow_field_valid");
    register_native("Navmesh_BuildGroupPathsToArea", "native_build_group_paths_to_area");
    register_native("Navmesh_RequestPath", "native_request_path");
    register_native("Navmesh_CancelPathRequest", "native_cancel_path_request");
    register_native("Navmesh_PathFollow_SetTarget", "native_pathfollow_set_target");
    register_native("Navmesh_PathFollow_GetTarget", "native_pathfollow_get_target");
    register_native("Navmesh_PathFollow_Advance", "native_pathfollow_advance");
    register_native("Navmesh_PathFollow_IsFinished", "native_pathfollow_is_finished");
    register_native("Navmesh_PathFollow_Reset", "native_pathfollow_reset");
    register_native("Navmesh_PathFollow_GetRemaining", "native_pathfollow_get_remaining");
}

public NavmeshBotPath_PluginInit()
{
    if(g_tPathCache == Invalid_Trie)
        g_tPathCache = TrieCreate();
    
    if(g_aPathCacheEntries == Invalid_Array)
        g_aPathCacheEntries = ArrayCreate(NavPathCacheEntry);
    
    if(g_aFlowFields == Invalid_Array)
        g_aFlowFields = ArrayCreate(NavFlowFieldEntry);
    
    if(g_aAsyncQueue == Invalid_Array)
        g_aAsyncQueue = ArrayCreate(NavAsyncRequestEntry);
    
    NavmeshBotPath_ResetPathFollowState();
}

public NavmeshBotPath_PluginEnd()
{
    NavmeshBotPath_StopAsyncQueue();
    NavmeshBotPath_ClearPathCacheInternal();
    NavmeshBotPath_ClearFlowFieldsInternal();
    NavmeshBotPath_ClearAsyncQueueInternal();
    NavmeshBotPath_ResetPathFollowState();
}

public NavmeshBotPath_BumpGeneration()
{
    g_iNavGeneration++;
    
    if(g_iNavGeneration <= 0)
        g_iNavGeneration = 1;
    
    NavmeshBotPath_ClearPathCacheInternal();
    NavmeshBotPath_ClearFlowFieldsInternal();
    NavmeshBotPath_ClearAsyncQueueInternal();
    NavmeshBotPath_ResetPathFollowState();
}

stock NavmeshBotPath_ClearPathCacheInternal()
{
    if(g_aPathCacheEntries != Invalid_Array)
    {
        new sEntry[NavPathCacheEntry];
        for(new i = 0; i < ArraySize(g_aPathCacheEntries); i++)
        {
            ArrayGetArray(g_aPathCacheEntries, i, sEntry);
            if(sEntry[CACHE_PATH] != Invalid_Array)
                ArrayDestroy(sEntry[CACHE_PATH]);
        }
        ArrayClear(g_aPathCacheEntries);
    }
    
    if(g_tPathCache != Invalid_Trie)
        TrieClear(g_tPathCache);
}

stock NavmeshBotPath_ClearFlowFieldsInternal()
{
    if(g_aFlowFields == Invalid_Array)
        return;
    
    new sField[NavFlowFieldEntry];
    for(new i = 0; i < ArraySize(g_aFlowFields); i++)
    {
        ArrayGetArray(g_aFlowFields, i, sField);
        
        if(sField[FLOW_NEXT_HOP] != Invalid_Array)
            ArrayDestroy(sField[FLOW_NEXT_HOP]);
        if(sField[FLOW_DISTANCE] != Invalid_Array)
            ArrayDestroy(sField[FLOW_DISTANCE]);
        
        sField[FLOW_VALID] = false;
        sField[FLOW_NEXT_HOP] = Invalid_Array;
        sField[FLOW_DISTANCE] = Invalid_Array;
        ArraySetArray(g_aFlowFields, i, sField);
    }
}

stock NavmeshBotPath_ClearAsyncQueueInternal()
{
    if(g_aAsyncQueue != Invalid_Array)
        ArrayClear(g_aAsyncQueue);
}

stock NavmeshBotPath_StopAsyncQueue()
{
    if(task_exists(NAVMESH_BOTPATH_TASK_ID))
        remove_task(NAVMESH_BOTPATH_TASK_ID);
    
    g_bAsyncQueueRunning = false;
}

stock NavmeshBotPath_ResetPathFollowState()
{
    for(new i = 1; i <= NAVMESH_BOTPATH_MAX_PLAYERS; i++)
    {
        g_aPathFollowState[i][FOLLOW_TARGET_AREA] = INVALID_NAV_AREA;
        g_aPathFollowState[i][FOLLOW_PATH] = Invalid_Array;
        g_aPathFollowState[i][FOLLOW_PATH_INDEX] = 0;
        g_aPathFollowState[i][FOLLOW_PATH_LENGTH] = 0;
        g_aPathFollowState[i][FOLLOW_GENERATION] = 0;
    }
}

stock NavmeshBotPath_EnsureInitialized()
{
    if(g_tPathCache == Invalid_Trie)
        g_tPathCache = TrieCreate();
    if(g_aPathCacheEntries == Invalid_Array)
        g_aPathCacheEntries = ArrayCreate(NavPathCacheEntry);
    if(g_aFlowFields == Invalid_Array)
        g_aFlowFields = ArrayCreate(NavFlowFieldEntry);
    if(g_aAsyncQueue == Invalid_Array)
        g_aAsyncQueue = ArrayCreate(NavAsyncRequestEntry);
}

stock NavmeshBotPath_CopyPath(Array:aSource, Array:aDest)
{
    ArrayClear(aDest);
    
    new sSegment[NavPathSegment];
    for(new i = 0; i < ArraySize(aSource); i++)
    {
        ArrayGetArray(aSource, i, sSegment);
        ArrayPushArray(aDest, sSegment);
    }
}

stock NavmeshBotPath_MakeCacheKey(iStartArea, iGoalArea, NavRouteType:routeType, szKey[], iMaxLen)
{
    formatex(szKey, iMaxLen, "%d:%d:%d", iStartArea, iGoalArea, _:routeType);
}

public bool:native_build_path_cached(const pPluginID, const iParams)
{
    new iStartArea = get_param(1);
    new iGoalArea = get_param(2);
    new Array:aPathOut = Array:get_param(3);
    new NavRouteType:routeType = (iParams >= 4) ? NavRouteType:get_param(4) : NAV_ROUTE_FASTEST;
    
    if(!IsValidArea(iStartArea) || !IsValidArea(iGoalArea) || aPathOut == Invalid_Array)
        return false;
    
    NavmeshBotPath_EnsureInitialized();
    
    new szKey[64], iEntryIndex;
    NavmeshBotPath_MakeCacheKey(iStartArea, iGoalArea, routeType, szKey, charsmax(szKey));
    
    if(TrieGetCell(g_tPathCache, szKey, iEntryIndex))
    {
        if(iEntryIndex >= 0 && iEntryIndex < ArraySize(g_aPathCacheEntries))
        {
            new sCached[NavPathCacheEntry];
            ArrayGetArray(g_aPathCacheEntries, iEntryIndex, sCached);
            
            if(sCached[CACHE_GENERATION] == g_iNavGeneration && sCached[CACHE_PATH] != Invalid_Array)
            {
                NavmeshBotPath_CopyPath(sCached[CACHE_PATH], aPathOut);
                return true;
            }
            
            if(sCached[CACHE_PATH] != Invalid_Array)
                ArrayDestroy(sCached[CACHE_PATH]);
            
            sCached[CACHE_PATH] = Invalid_Array;
            ArraySetArray(g_aPathCacheEntries, iEntryIndex, sCached);
            TrieDeleteKey(g_tPathCache, szKey);
        }
    }
    
    new Array:aComputedPath = ArrayCreate(NavPathSegment);
    if(!BuildPathAStar(iStartArea, iGoalArea, aComputedPath, routeType))
    {
        ArrayDestroy(aComputedPath);
        ArrayClear(aPathOut);
        return false;
    }
    
    NavmeshBotPath_CopyPath(aComputedPath, aPathOut);
    
    new sNewEntry[NavPathCacheEntry];
    sNewEntry[CACHE_START_AREA] = iStartArea;
    sNewEntry[CACHE_GOAL_AREA] = iGoalArea;
    sNewEntry[CACHE_ROUTE_TYPE] = routeType;
    sNewEntry[CACHE_GENERATION] = g_iNavGeneration;
    sNewEntry[CACHE_PATH] = aComputedPath;
    
    new iNewIndex = ArraySize(g_aPathCacheEntries);
    ArrayPushArray(g_aPathCacheEntries, sNewEntry);
    TrieSetCell(g_tPathCache, szKey, iNewIndex);
    
    return true;
}

public native_clear_path_cache(const pPluginID, const iParams)
{
    NavmeshBotPath_ClearPathCacheInternal();
}

stock bool:NavmeshBotPath_IsFlowFieldValidInternal(iFlowFieldId)
{
    if(g_aFlowFields == Invalid_Array)
        return false;
    
    new iIndex = iFlowFieldId - 1;
    if(iIndex < 0 || iIndex >= ArraySize(g_aFlowFields))
        return false;
    
    new sField[NavFlowFieldEntry];
    ArrayGetArray(g_aFlowFields, iIndex, sField);
    
    return sField[FLOW_VALID] &&
        sField[FLOW_GENERATION] == g_iNavGeneration &&
        sField[FLOW_NEXT_HOP] != Invalid_Array &&
        sField[FLOW_DISTANCE] != Invalid_Array;
}

stock NavmeshBotPath_FreeFlowFieldByIndex(iIndex)
{
    if(g_aFlowFields == Invalid_Array || iIndex < 0 || iIndex >= ArraySize(g_aFlowFields))
        return;
    
    new sField[NavFlowFieldEntry];
    ArrayGetArray(g_aFlowFields, iIndex, sField);
    
    if(sField[FLOW_NEXT_HOP] != Invalid_Array)
        ArrayDestroy(sField[FLOW_NEXT_HOP]);
    if(sField[FLOW_DISTANCE] != Invalid_Array)
        ArrayDestroy(sField[FLOW_DISTANCE]);
    
    sField[FLOW_VALID] = false;
    sField[FLOW_NEXT_HOP] = Invalid_Array;
    sField[FLOW_DISTANCE] = Invalid_Array;
    ArraySetArray(g_aFlowFields, iIndex, sField);
}

stock NavmeshBotPath_BuildFlowFieldInternal(iGoalArea, NavRouteType:routeType)
{
    if(!IsValidArea(iGoalArea))
        return 0;
    
    NavmeshBotPath_EnsureInitialized();
    
    new iAreaCount = ArraySize(g_aNavAreas);
    new Array:aNextHop = ArrayCreate();
    new Array:aDistance = ArrayCreate();
    for(new i = 0; i < iAreaCount; i++)
    {
        ArrayPushCell(aNextHop, INVALID_NAV_AREA);
        ArrayPushCell(aDistance, _:NAVMESH_BOTPATH_INFINITY);
    }
    
    // Build reverse adjacency once: incoming[to] = list(from)
    new Array:aIncoming = ArrayCreate();
    for(new i = 0; i < iAreaCount; i++)
        ArrayPushCell(aIncoming, Invalid_Array);
    
    new sArea[NavArea];
    for(new iArea = 0; iArea < iAreaCount; iArea++)
    {
        if(!IsValidArea(iArea))
            continue;
        
        ArrayGetArray(g_aNavAreas, iArea, sArea);
        for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
        {
            new Array:aConnect = GetAreaConnectArray(sArea, dir);
            if(aConnect == Invalid_Array)
                continue;
            
            for(new i = 0; i < ArraySize(aConnect); i++)
            {
                new sConnect[NavConnect];
                ArrayGetArray(aConnect, i, sConnect);
                
                new iToArea = sConnect[NAV_CONNECT_AREA];
                if(!IsValidArea(iToArea))
                    continue;
                
                new Array:aPreds = Array:ArrayGetCell(aIncoming, iToArea);
                if(aPreds == Invalid_Array)
                {
                    aPreds = ArrayCreate();
                    ArraySetCell(aIncoming, iToArea, aPreds);
                }
                
                ArrayPushCell(aPreds, iArea);
            }
        }
    }
    
    ArraySetCell(aDistance, iGoalArea, _:0.0);
    new Array:aOpenHeap = ArrayCreate(3);
    HeapPushArea(aOpenHeap, iGoalArea, 0.0, 0.0);
    
    while(ArraySize(aOpenHeap) > 0)
    {
        new Float:fCurrentDist;
        new iCurrent = HeapPopArea(aOpenHeap, fCurrentDist);
        if(iCurrent == INVALID_NAV_AREA)
            break;
        
        new Float:fBestDist = Float:ArrayGetCell(aDistance, iCurrent);
        if(fCurrentDist > fBestDist + 0.0001)
            continue;
        
        new Array:aPreds = Array:ArrayGetCell(aIncoming, iCurrent);
        if(aPreds == Invalid_Array)
            continue;
        
        for(new i = 0; i < ArraySize(aPreds); i++)
        {
            new iPred = ArrayGetCell(aPreds, i);
            if(!IsValidArea(iPred))
                continue;
            
            new Float:fCandidate = fBestDist + Math_GetMoveCost(iPred, iCurrent, routeType);
            new Float:fPredDist = Float:ArrayGetCell(aDistance, iPred);
            if(fCandidate < fPredDist)
            {
                ArraySetCell(aDistance, iPred, _:fCandidate);
                ArraySetCell(aNextHop, iPred, iCurrent);
                HeapPushArea(aOpenHeap, iPred, fCandidate, 0.0);
            }
        }
    }
    
    ArrayDestroy(aOpenHeap);
    
    for(new i = 0; i < iAreaCount; i++)
    {
        new Array:aPreds = Array:ArrayGetCell(aIncoming, i);
        if(aPreds != Invalid_Array)
            ArrayDestroy(aPreds);
    }
    ArrayDestroy(aIncoming);
    
    new sField[NavFlowFieldEntry];
    sField[FLOW_GOAL_AREA] = iGoalArea;
    sField[FLOW_ROUTE_TYPE] = routeType;
    sField[FLOW_GENERATION] = g_iNavGeneration;
    sField[FLOW_VALID] = true;
    sField[FLOW_NEXT_HOP] = aNextHop;
    sField[FLOW_DISTANCE] = aDistance;
    
    ArrayPushArray(g_aFlowFields, sField);
    return ArraySize(g_aFlowFields);
}

public native_build_flow_field(const pPluginID, const iParams)
{
    new iGoalArea = get_param(1);
    new NavRouteType:routeType = (iParams >= 2) ? NavRouteType:get_param(2) : NAV_ROUTE_FASTEST;
    return NavmeshBotPath_BuildFlowFieldInternal(iGoalArea, routeType);
}

stock bool:NavmeshBotPath_BuildPathFromFlowFieldInternal(iFlowFieldId, iStartArea, Array:aPathOut)
{
    if(!NavmeshBotPath_IsFlowFieldValidInternal(iFlowFieldId) || !IsValidArea(iStartArea) || aPathOut == Invalid_Array)
        return false;
    
    new iFlowIndex = iFlowFieldId - 1;
    new sField[NavFlowFieldEntry];
    ArrayGetArray(g_aFlowFields, iFlowIndex, sField);
    
    ArrayClear(aPathOut);
    
    new iGoalArea = sField[FLOW_GOAL_AREA];
    new iCurrentArea = iStartArea;
    new iPrevArea = INVALID_NAV_AREA;
    new iMaxSteps = ArraySize(g_aNavAreas) + 1;
    
    for(new iStep = 0; iStep < iMaxSteps; iStep++)
    {
        if(!IsValidArea(iCurrentArea))
        {
            ArrayClear(aPathOut);
            return false;
        }
        
        new sArea[NavArea], sSegment[NavPathSegment];
        ArrayGetArray(g_aNavAreas, iCurrentArea, sArea);
        
        sSegment[NAV_PATH_AREA] = iCurrentArea;
        sSegment[NAV_PATH_HOW] = (iPrevArea == INVALID_NAV_AREA)
            ? NAV_TRAVERSE_NORTH
            : NavTraverseType:GetDirectionFromTo(iPrevArea, iCurrentArea);
        sSegment[NAV_PATH_POS_X] = sArea[NAV_AREA_CENTER_X];
        sSegment[NAV_PATH_POS_Y] = sArea[NAV_AREA_CENTER_Y];
        sSegment[NAV_PATH_POS_Z] = sArea[NAV_AREA_CENTER_Z];
        ArrayPushArray(aPathOut, sSegment);
        
        if(iCurrentArea == iGoalArea)
            return true;
        
        new iNextArea = ArrayGetCell(sField[FLOW_NEXT_HOP], iCurrentArea);
        if(iNextArea == INVALID_NAV_AREA)
        {
            ArrayClear(aPathOut);
            return false;
        }
        
        iPrevArea = iCurrentArea;
        iCurrentArea = iNextArea;
    }
    
    ArrayClear(aPathOut);
    return false;
}

public bool:native_get_path_from_flow_field(const pPluginID, const iParams)
{
    new iFlowFieldId = get_param(1);
    new iStartArea = get_param(2);
    new Array:aPathOut = Array:get_param(3);
    
    return NavmeshBotPath_BuildPathFromFlowFieldInternal(iFlowFieldId, iStartArea, aPathOut);
}

public bool:native_destroy_flow_field(const pPluginID, const iParams)
{
    new iFlowFieldId = get_param(1);
    
    if(g_aFlowFields == Invalid_Array)
        return false;
    
    new iIndex = iFlowFieldId - 1;
    if(iIndex < 0 || iIndex >= ArraySize(g_aFlowFields))
        return false;
    
    new sField[NavFlowFieldEntry];
    ArrayGetArray(g_aFlowFields, iIndex, sField);
    if(!sField[FLOW_VALID])
        return false;
    
    NavmeshBotPath_FreeFlowFieldByIndex(iIndex);
    return true;
}

public bool:native_is_flow_field_valid(const pPluginID, const iParams)
{
    return NavmeshBotPath_IsFlowFieldValidInternal(get_param(1));
}

public native_build_group_paths_to_area(const pPluginID, const iParams)
{
    new iGoalArea = get_param(1);
    new iStartCount = get_param(3);
    new Array:aPathsOut = Array:get_param(4);
    new Array:aStatusOut = Array:get_param(5);
    new NavRouteType:routeType = (iParams >= 6) ? NavRouteType:get_param(6) : NAV_ROUTE_FASTEST;
    
    if(!IsValidArea(iGoalArea) || iStartCount <= 0 || aPathsOut == Invalid_Array || aStatusOut == Invalid_Array)
        return 0;
    
    if(iStartCount > 256)
        iStartCount = 256;
    
    new iFlowFieldId = NavmeshBotPath_BuildFlowFieldInternal(iGoalArea, routeType);
    if(iFlowFieldId == 0)
        return 0;
    
    new iStartAreas[256];
    get_array(2, iStartAreas, iStartCount);
    
    ArrayClear(aPathsOut);
    ArrayClear(aStatusOut);
    
    for(new i = 0; i < iStartCount; i++)
    {
        new Array:aPath = ArrayCreate(NavPathSegment);
        new bool:bOk = NavmeshBotPath_BuildPathFromFlowFieldInternal(iFlowFieldId, iStartAreas[i], aPath);
        
        ArrayPushCell(aPathsOut, _:aPath);
        ArrayPushCell(aStatusOut, bOk);
    }
    
    return iFlowFieldId;
}

stock NavmeshBotPath_InvokeAsyncCallback(const sRequest[NavAsyncRequestEntry], bool:bSuccess, Array:aPath)
{
    if(!sRequest[REQUEST_CALLBACK][0])
    {
        if(aPath != Invalid_Array)
            ArrayDestroy(aPath);
        return;
    }
    
    new iFunction = get_func_id(sRequest[REQUEST_CALLBACK], sRequest[REQUEST_PLUGIN_ID]);
    if(iFunction == -1)
    {
        if(aPath != Invalid_Array)
            ArrayDestroy(aPath);
        return;
    }
    
    callfunc_begin_i(iFunction, sRequest[REQUEST_PLUGIN_ID]);
    callfunc_push_int(sRequest[REQUEST_ID]);
    callfunc_push_int(_:bSuccess);
    callfunc_push_int(_:aPath);
    callfunc_end();
}

stock NavmeshBotPath_StartAsyncQueue()
{
    if(g_bAsyncQueueRunning)
        return;
    
    set_task(0.05, "NavmeshBotPath_ProcessQueue", NAVMESH_BOTPATH_TASK_ID, "", 0, "b");
    g_bAsyncQueueRunning = true;
}

public NavmeshBotPath_ProcessQueue()
{
    if(g_aAsyncQueue == Invalid_Array || ArraySize(g_aAsyncQueue) == 0)
    {
        NavmeshBotPath_StopAsyncQueue();
        return;
    }
    
    new iProcessed = 0;
    while(iProcessed < NAVMESH_BOTPATH_FRAME_BUDGET && ArraySize(g_aAsyncQueue) > 0)
    {
        new sRequest[NavAsyncRequestEntry];
        ArrayGetArray(g_aAsyncQueue, 0, sRequest);
        ArrayDeleteItem(g_aAsyncQueue, 0);
        
        iProcessed++;
        
        if(sRequest[REQUEST_CANCELLED])
            continue;
        
        new Array:aPath = ArrayCreate(NavPathSegment);
        new bool:bSuccess = false;
        
        if(sRequest[REQUEST_GENERATION] == g_iNavGeneration &&
           IsValidArea(sRequest[REQUEST_START_AREA]) &&
           IsValidArea(sRequest[REQUEST_GOAL_AREA]))
        {
            bSuccess = BuildPathAStar(
                sRequest[REQUEST_START_AREA],
                sRequest[REQUEST_GOAL_AREA],
                aPath,
                sRequest[REQUEST_ROUTE_TYPE]
            );
        }
        
        NavmeshBotPath_InvokeAsyncCallback(sRequest, bSuccess, aPath);
    }
    
    if(ArraySize(g_aAsyncQueue) == 0)
        NavmeshBotPath_StopAsyncQueue();
}

public native_request_path(const pPluginID, const iParams)
{
    new iStartArea = get_param(1);
    new iGoalArea = get_param(2);
    new NavRouteType:routeType = (iParams >= 4) ? NavRouteType:get_param(4) : NAV_ROUTE_FASTEST;
    
    if(!IsValidArea(iStartArea) || !IsValidArea(iGoalArea))
        return 0;
    
    new szCallback[64];
    get_string(3, szCallback, charsmax(szCallback));
    if(!szCallback[0])
        return 0;
    
    NavmeshBotPath_EnsureInitialized();
    
    new sRequest[NavAsyncRequestEntry];
    sRequest[REQUEST_ID] = g_iNextAsyncRequestID++;
    sRequest[REQUEST_START_AREA] = iStartArea;
    sRequest[REQUEST_GOAL_AREA] = iGoalArea;
    sRequest[REQUEST_ROUTE_TYPE] = routeType;
    sRequest[REQUEST_GENERATION] = g_iNavGeneration;
    sRequest[REQUEST_PLUGIN_ID] = pPluginID;
    sRequest[REQUEST_CANCELLED] = false;
    copy(sRequest[REQUEST_CALLBACK], 63, szCallback);
    
    ArrayPushArray(g_aAsyncQueue, sRequest);
    NavmeshBotPath_StartAsyncQueue();
    
    return sRequest[REQUEST_ID];
}

public bool:native_cancel_path_request(const pPluginID, const iParams)
{
    new iRequestID = get_param(1);
    
    if(g_aAsyncQueue == Invalid_Array || iRequestID <= 0)
        return false;
    
    new sRequest[NavAsyncRequestEntry];
    for(new i = 0; i < ArraySize(g_aAsyncQueue); i++)
    {
        ArrayGetArray(g_aAsyncQueue, i, sRequest);
        if(sRequest[REQUEST_ID] == iRequestID)
        {
            sRequest[REQUEST_CANCELLED] = true;
            ArraySetArray(g_aAsyncQueue, i, sRequest);
            return true;
        }
    }
    
    return false;
}

stock bool:NavmeshBotPath_IsValidFollowPlayer(iPlayer)
{
    return (iPlayer >= 1 && iPlayer <= NAVMESH_BOTPATH_MAX_PLAYERS);
}

stock NavmeshBotPath_ResetFollowPlayer(iPlayer)
{
    if(!NavmeshBotPath_IsValidFollowPlayer(iPlayer))
        return;
    
    g_aPathFollowState[iPlayer][FOLLOW_TARGET_AREA] = INVALID_NAV_AREA;
    g_aPathFollowState[iPlayer][FOLLOW_PATH] = Invalid_Array;
    g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX] = 0;
    g_aPathFollowState[iPlayer][FOLLOW_PATH_LENGTH] = 0;
    g_aPathFollowState[iPlayer][FOLLOW_GENERATION] = 0;
}

public bool:native_pathfollow_set_target(const pPluginID, const iParams)
{
    new iPlayer = get_param(1);
    new Array:aPath = Array:get_param(2);
    
    if(!NavmeshBotPath_IsValidFollowPlayer(iPlayer) || aPath == Invalid_Array)
        return false;
    
    new iLen = ArraySize(aPath);
    if(iLen <= 0)
    {
        NavmeshBotPath_ResetFollowPlayer(iPlayer);
        return false;
    }
    
    new sLast[NavPathSegment];
    ArrayGetArray(aPath, iLen - 1, sLast);
    
    g_aPathFollowState[iPlayer][FOLLOW_TARGET_AREA] = sLast[NAV_PATH_AREA];
    g_aPathFollowState[iPlayer][FOLLOW_PATH] = aPath;
    g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX] = 0;
    g_aPathFollowState[iPlayer][FOLLOW_PATH_LENGTH] = iLen;
    g_aPathFollowState[iPlayer][FOLLOW_GENERATION] = g_iNavGeneration;
    
    return true;
}

public bool:native_pathfollow_get_target(const pPluginID, const iParams)
{
    new iPlayer = get_param(1);
    
    if(!NavmeshBotPath_IsValidFollowPlayer(iPlayer))
        return false;
    
    if(g_aPathFollowState[iPlayer][FOLLOW_GENERATION] != g_iNavGeneration)
    {
        NavmeshBotPath_ResetFollowPlayer(iPlayer);
        return false;
    }
    
    set_param_byref(2, g_aPathFollowState[iPlayer][FOLLOW_TARGET_AREA]);
    set_param_byref(3, g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX]);
    set_param_byref(4, g_aPathFollowState[iPlayer][FOLLOW_PATH_LENGTH]);
    
    return g_aPathFollowState[iPlayer][FOLLOW_PATH] != Invalid_Array;
}

public bool:native_pathfollow_advance(const pPluginID, const iParams)
{
    new iPlayer = get_param(1);
    
    if(!NavmeshBotPath_IsValidFollowPlayer(iPlayer))
        return false;
    
    if(g_aPathFollowState[iPlayer][FOLLOW_GENERATION] != g_iNavGeneration)
    {
        NavmeshBotPath_ResetFollowPlayer(iPlayer);
        return false;
    }
    
    if(g_aPathFollowState[iPlayer][FOLLOW_PATH] == Invalid_Array)
        return false;
    
    if(g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX] < g_aPathFollowState[iPlayer][FOLLOW_PATH_LENGTH] - 1)
        g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX]++;
    
    return (g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX] >= g_aPathFollowState[iPlayer][FOLLOW_PATH_LENGTH] - 1);
}

public bool:native_pathfollow_is_finished(const pPluginID, const iParams)
{
    new iPlayer = get_param(1);
    
    if(!NavmeshBotPath_IsValidFollowPlayer(iPlayer))
        return true;
    
    if(g_aPathFollowState[iPlayer][FOLLOW_GENERATION] != g_iNavGeneration)
    {
        NavmeshBotPath_ResetFollowPlayer(iPlayer);
        return true;
    }
    
    if(g_aPathFollowState[iPlayer][FOLLOW_PATH] == Invalid_Array)
        return true;
    
    return (g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX] >= g_aPathFollowState[iPlayer][FOLLOW_PATH_LENGTH] - 1);
}

public native_pathfollow_reset(const pPluginID, const iParams)
{
    NavmeshBotPath_ResetFollowPlayer(get_param(1));
}

public native_pathfollow_get_remaining(const pPluginID, const iParams)
{
    new iPlayer = get_param(1);
    
    if(!NavmeshBotPath_IsValidFollowPlayer(iPlayer))
        return 0;
    
    if(g_aPathFollowState[iPlayer][FOLLOW_GENERATION] != g_iNavGeneration)
    {
        NavmeshBotPath_ResetFollowPlayer(iPlayer);
        return 0;
    }
    
    if(g_aPathFollowState[iPlayer][FOLLOW_PATH] == Invalid_Array)
        return 0;
    
    new iRemaining = g_aPathFollowState[iPlayer][FOLLOW_PATH_LENGTH] - 1 - g_aPathFollowState[iPlayer][FOLLOW_PATH_INDEX];
    return (iRemaining > 0) ? iRemaining : 0;
}

#endif
