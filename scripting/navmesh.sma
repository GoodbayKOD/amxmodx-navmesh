#include <amxmodx>
#include <fakemeta>
#include <engine>
#include <file>
#include <xs>

#include <nav/navmesh_const>
#include <nav/navmesh_stocks>

#pragma semicolon 1

// ============================================================================
// Plugin Constants
// ============================================================================

#define PLUGIN_NAME     "NavMesh"
#define PLUGIN_VERSION  "2.0"
#define PLUGIN_AUTHOR   "Goodbay"

const MAX_APPROACH_AREAS = 16;  // Maximum approach areas per area

#if !defined MaxClients
    #define MaxClients  get_maxplayers()
#endif

#define is_user_valid(%1)						(1 <= %1 <= MaxClients)

// ============================================================================
// Global Variables
// ============================================================================

new Array:g_aNavAreas;      // Dynamic array of NavArea
new Array:g_aNavLadders;    // Dynamic array of NavLadder

new g_nGrid[NavAreaGrid];           // Spatial grid for fast search
new g_nPlace[NavPlaceDirectory];    // Place names directory

new bool:g_bNavLoaded;  // Navmesh load state
new g_iNavAreaCount;    // Number of loaded areas
new g_iNextAreaID = 1;  // Next available ID for new areas

// Per-entity repath cooldown timers (mirrors CCSBot::m_repathTimer).
// Indexed by entity index; value is the next gametime allowed to recompute path.
new Float:g_fRepathTimer[2048];

// ============================================================================
// Plugin Init
// ============================================================================

public plugin_natives()
{
    // Register natives
    register_native("Navmesh_Load", "native_load");
    register_native("Navmesh_Unload", "native_unload");
    register_native("Navmesh_IsLoaded", "native_is_loaded");
    register_native("Navmesh_GetAreaCount", "native_get_area_count");
    register_native("Navmesh_GetNearestArea", "native_get_nearest_area");
    register_native("Navmesh_GetAreaByID", "native_get_area_by_id");
    register_native("Navmesh_GetAreaID", "native_get_area_id");
    register_native("Navmesh_GetAreaCenter", "native_get_area_center");
    register_native("Navmesh_GetAreaExtent", "native_get_area_extent");
    register_native("Navmesh_GetAreaAttributes", "native_get_area_attributes");
    register_native("Navmesh_IsPointInArea", "native_is_point_in_area");
    register_native("Navmesh_GetAreaZ", "native_get_area_z");
    register_native("Navmesh_GetMoveCost", "native_get_move_cost");
    register_native("Navmesh_GetAdjacentCount", "native_get_adjacent_count");
    register_native("Navmesh_GetAdjacentArea", "native_get_adjacent_area");
    register_native("Navmesh_IsConnected", "native_is_connected");
    register_native("Navmesh_BuildPathFromArea", "native_build_path_from_area");
    register_native("Navmesh_BuildPath", "native_build_path");
    register_native("Navmesh_GetPathLength", "native_get_path_length");
    register_native("Navmesh_GetPathSegment", "native_get_path_segment");
    register_native("Navmesh_ClearPath", "native_clear_path");
    register_native("Navmesh_GetPathDistance", "native_get_path_distance");
    register_native("Navmesh_IsAtEndOfPath", "native_is_at_end_of_path");
    register_native("Navmesh_GetPointAlongPath", "native_get_point_along_path");
    register_native("Navmesh_GetSegmentIndexAlongPath", "native_get_segment_index_along_path");
    register_native("Navmesh_FindClosestPointOnPath", "native_find_closest_point_on_path");
    register_native("Navmesh_TravelDistance", "native_travel_distance");
    register_native("Navmesh_OptimizePath", "native_optimize_path");
    register_native("Navmesh_ComputePath", "native_compute_path");
    register_native("Navmesh_UpdatePathMovement", "native_update_path_movement");
    register_native("Navmesh_ShouldJump", "native_should_jump");
    register_native("Navmesh_ResetRepathTimer", "native_reset_repath_timer");
    register_native("Navmesh_GetClosestPointInArea", "native_get_closest_point_in_area");
    register_native("Navmesh_GetDistanceSquaredToArea", "native_get_distance_squared_to_area");
    register_native("Navmesh_GetRandomArea", "native_get_random_area");
    register_native("Navmesh_GetRandomPositionInArea", "native_get_random_position_in_area");
    
    // New functions
    register_native("Navmesh_GetAreaCorner", "native_get_area_corner");
    register_native("Navmesh_IsAreaOverlapping", "native_is_area_overlapping");
    register_native("Navmesh_AreAreasOverlapping", "native_are_areas_overlapping");
    register_native("Navmesh_ComputePortal", "native_compute_portal");
    register_native("Navmesh_ComputeClosestPointInPortal", "native_compute_closest_point_in_portal");
    register_native("Navmesh_GetAreaPlace", "native_get_area_place");
    register_native("Navmesh_GetPlaceName", "native_get_place_name");
    register_native("Navmesh_GetApproachCount", "native_get_approach_count");
    register_native("Navmesh_GetApproachInfo", "native_get_approach_info");
    register_native("Navmesh_GetLadderCount", "native_get_ladder_count");
    register_native("Navmesh_GetLadderInfo", "native_get_ladder_info");
    register_native("Navmesh_Contains", "native_contains");
    
    // Editing functions
    register_native("Navmesh_CreateArea", "native_create_area");
    register_native("Navmesh_DeleteArea", "native_delete_area");
    register_native("Navmesh_SetAreaAttributes", "native_set_area_attributes");
    register_native("Navmesh_ConnectAreas", "native_connect_areas");
    register_native("Navmesh_DisconnectAreas", "native_disconnect_areas");
    register_native("Navmesh_SetCornerZ", "native_set_corner_z");
    register_native("Navmesh_SetAreaExtent", "native_set_area_extent");
    register_native("Navmesh_Save", "native_save");
    register_native("Navmesh_Init", "native_init");
    register_native("Navmesh_SplitArea", "native_split_area");
    register_native("Navmesh_MergeAreas", "native_merge_areas");
    register_native("Navmesh_SpliceAreas", "native_splice_areas");
}

public plugin_init()
{
    register_plugin("navmesh", "1.0b", "Goodbay");
}

public plugin_end()
{
    if(g_bNavLoaded)
        Navmesh_UnloadInternal();
}

// ============================================================================
// Natives - Management
// ============================================================================

public NavErrorType:native_load(plugin_id, num_params)
{
    new szMapName[32];
    get_string(1, szMapName, charsmax(szMapName));
    
    return Navmesh_LoadInternal(szMapName);
}

public native_unload(plugin_id, num_params)
{
    if(g_bNavLoaded)
        Navmesh_UnloadInternal();
}

public bool:native_init(plugin_id, num_params)
{
    return Navmesh_InitEmpty();
}

public bool:native_is_loaded(plugin_id, num_params)
{
    return g_bNavLoaded;
}

public native_get_area_count(plugin_id, num_params)
{
    return g_iNavAreaCount;
}

// ============================================================================
// Natives - Area Search
// ============================================================================

public native_get_nearest_area(plugin_id, num_params)
{
    new Float:vOrigin[3];
    get_array_f(1, vOrigin, 3);
    
    new Float:fMaxDist = get_param_f(2);
    new Float:fBeneathLimit = get_param_f(3);
    
    return Navmesh_GetNearestAreaInternal(vOrigin, fMaxDist, fBeneathLimit);
}

public native_get_area_by_id(plugin_id, num_params)
{
    // Uses hash search O(1) instead of linear O(n)
    return FindAreaByID(get_param(1));
}

public native_get_area_id(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return 0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return sArea[NAV_AREA_ID];
}

// ============================================================================
// Natives - Area Information
// ============================================================================

public bool:native_get_area_center(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:vCenter[3];
    vCenter[0] = Float:sArea[NAV_AREA_CENTER_X];
    vCenter[1] = Float:sArea[NAV_AREA_CENTER_Y];
    vCenter[2] = Float:sArea[NAV_AREA_CENTER_Z];
    
    set_array_f(2, vCenter, 3);
    return true;
}

public bool:native_get_area_extent(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:vMins[3], Float:vMaxs[3];
    vMins[0] = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    vMins[1] = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    vMins[2] = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z];
    
    vMaxs[0] = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    vMaxs[1] = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    vMaxs[2] = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z];
    
    set_array_f(2, vMins, 3);
    set_array_f(3, vMaxs, 3);
    return true;
}

public NavAttributeType:native_get_area_attributes(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return NavAttributeType:0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return NavAttributeType:sArea[NAV_AREA_ATTRIBUTES];
}

public bool:native_is_point_in_area(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new Float:vPoint[3];
    get_array_f(2, vPoint, 3);
    
    return Navmesh_IsPointInAreaInternal(iAreaIndex, vPoint);
}

public Float:native_get_area_z(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return 0.0;
    
    new Float:fX = get_param_f(2);
    new Float:fY = get_param_f(3);
    
    return Navmesh_GetAreaZInternal(iAreaIndex, fX, fY);
}

public Float:native_get_move_cost(plugin_id, num_params)
{
    new iAreaFrom = get_param(1);
    new iAreaTo = get_param(2);

    if(!IsValidAreaIndex(iAreaFrom) || !IsValidAreaIndex(iAreaTo))
        return 0.0;

    return GetMoveCost(iAreaFrom, iAreaTo);
}

public bool:native_contains(plugin_id, num_params)
{
    new entity = get_param(1);

    if(entity <= 0 || !is_user_valid(entity) || !is_valid_ent(entity))
        return false;

    new iAreaIndex = get_param(2);

    if(!IsValidAreaIndex(iAreaIndex))
        return false;

    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);

    new Float:vPos[3], Float:vCenter[3];
    entity_get_vector(entity, EV_VEC_origin, vPos);
    
    vCenter[0] = Float:sArea[NAV_AREA_CENTER_X];
    vCenter[1] = Float:sArea[NAV_AREA_CENTER_Y];
    vCenter[2] = Float:sArea[NAV_AREA_CENTER_Z];

    if(!xs_vec_nearlyequal(vPos, vCenter))
        return false;

    return true;
}

// ============================================================================
// Natives - Connections
// ============================================================================

public native_get_adjacent_count(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new NavDirType:dir = NavDirType:get_param(2);
    
    if(!IsValidAreaIndex(iAreaIndex) || dir >= NUM_NAV_DIRECTIONS)
        return 0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Array:aConnect = GetAreaConnectArray(sArea, dir);
    return aConnect != Invalid_Array ? ArraySize(aConnect) : 0;
}

public native_get_adjacent_area(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new NavDirType:dir = NavDirType:get_param(2);
    new iIndex = get_param(3);
    
    if(!IsValidAreaIndex(iAreaIndex) || dir >= NUM_NAV_DIRECTIONS)
        return Invalid_Area;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Array:aConnect = GetAreaConnectArray(sArea, dir);
    if(aConnect == Invalid_Array || iIndex < 0 || iIndex >= ArraySize(aConnect))
        return Invalid_Area;
    
    new sConnect[NavConnect];
    ArrayGetArray(aConnect, iIndex, sConnect);
    return sConnect[NAV_CONNECT_AREA];
}

public bool:native_is_connected(plugin_id, num_params)
{
    new iAreaIndex1 = get_param(1);
    new iAreaIndex2 = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidAreaIndex(iAreaIndex1) || !IsValidAreaIndex(iAreaIndex2))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex1, sArea);
    
    new Array:aConnect = GetAreaConnectArray(sArea, dir);
    if(aConnect == Invalid_Array)
        return false;
    
    new sConnect[NavConnect];
    for(new i = 0; i < ArraySize(aConnect); i++)
    {
        ArrayGetArray(aConnect, i, sConnect);
        if(sConnect[NAV_CONNECT_AREA] == iAreaIndex2)
            return true;
    }
    
    return false;
}

// ============================================================================
// Natives - Pathfinding
// ============================================================================

public bool:native_build_path_from_area(plugin_id, num_params)
{
    new iStartArea = get_param(1);
    new iGoalArea = get_param(2);
    new Array:aPathOut = Array:get_param(3);
    
    if(!IsValidAreaIndex(iStartArea) || !IsValidAreaIndex(iGoalArea))
        return false;
    
    if(aPathOut == Invalid_Array)
        return false;
    
    ArrayClear(aPathOut);
    
    // No real start/goal positions for this area-only API; use area centers.
    new sStart[NavArea], sGoal[NavArea];
    ArrayGetArray(g_aNavAreas, iStartArea, sStart);
    ArrayGetArray(g_aNavAreas, iGoalArea, sGoal);

    new Float:vStart[3], Float:vGoal[3];
    vStart[0] = Float:sStart[NAV_AREA_CENTER_X];
    vStart[1] = Float:sStart[NAV_AREA_CENTER_Y];
    vStart[2] = Float:sStart[NAV_AREA_CENTER_Z];

    vGoal[0] = Float:sGoal[NAV_AREA_CENTER_X];
    vGoal[1] = Float:sGoal[NAV_AREA_CENTER_Y];
    vGoal[2] = Float:sGoal[NAV_AREA_CENTER_Z];
    
    return BuildPathAStar(iStartArea, iGoalArea, aPathOut, vStart, vGoal);
}

public bool:native_build_path(plugin_id, num_params)
{
    new Float:vStart[3], Float:vGoal[3];
    get_array_f(1, vStart, 3);
    get_array_f(2, vGoal, 3);

    new Array:aPathOut = Array:get_param(3);
    
    if(aPathOut == Invalid_Array)
        return false;
    
    // Find nearest areas
    new iStartArea = Navmesh_GetNearestAreaInternal(vStart, 500.0, 120.0);
    new iGoalArea = Navmesh_GetNearestAreaInternal(vGoal, 500.0, 120.0);
    
    if(iStartArea == Invalid_Area || iGoalArea == Invalid_Area)
        return false;
    
    ArrayClear(aPathOut);
    
    return BuildPathAStar(iStartArea, iGoalArea, aPathOut, vStart, vGoal);
}

public native_get_path_length(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);
    return aPath != Invalid_Array ? ArraySize(aPath) : 0;
}

public bool:native_get_path_segment(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);
    new iIndex = get_param(2);
    
    if(aPath == Invalid_Array || iIndex < 0 || iIndex >= ArraySize(aPath))
        return false;
    
    new sSegment[NavPathSegment];
    ArrayGetArray(aPath, iIndex, sSegment);
    
    new Float:vPos[3];
    vPos[0] = Float:sSegment[NAV_PATH_POS_X];
    vPos[1] = Float:sSegment[NAV_PATH_POS_Y];
    vPos[2] = Float:sSegment[NAV_PATH_POS_Z];
    
    set_array_f(3, vPos, 3);
    set_param_byref(4, _:sSegment[NAV_PATH_HOW]);
    set_param_byref(5, sSegment[NAV_PATH_AREA]);
    
    return true;
}

public native_clear_path(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);

    if(aPath != Invalid_Array)
        ArrayClear(aPath);
}

// ----------------------------------------------------------------------------
// CCSBot::ComputePath / UpdatePathMovement / ShouldJump
// ----------------------------------------------------------------------------

// Resets the per-entity repath cooldown (call on spawn/death).
public native_reset_repath_timer(plugin_id, num_params)
{
    new entity = get_param(1);

    if(entity > 0 && entity < sizeof(g_fRepathTimer))
        g_fRepathTimer[entity] = 0.0;
}

// Builds an A* path from `vStart` to `vGoal` (or `goalArea`) and stores it in `path`.
// Throttles per-entity repath frequency to spread CPU load (mirrors CCSBot::ComputePath).
// Returns true if a path was built, false if throttled / no start area / no path.
public bool:native_compute_path(plugin_id, num_params)
{
    new entity = get_param(1);
    
    new Float:vStart[3];
    get_array_f(2, vStart, 3);
    
    new iGoalArea = get_param(3);
    
    new Float:vGoal[3];
    get_array_f(4, vGoal, 3);
    
    new Array:aPath = Array:get_param(5);
    new NavRouteType:route = NavRouteType:get_param(6);

    #pragma unused route
    new Float:fRepathDelay = get_param_f(7);
    
    if(aPath == Invalid_Array || !g_bNavLoaded)
        return false;
    
    // Per-entity repath cooldown
    if(entity > 0 && entity < sizeof(g_fRepathTimer))
    {
        new Float:fNow = get_gametime();

        if(fNow < g_fRepathTimer[entity])
            return false; // throttled - keep using existing path
        
        if(fRepathDelay <= 0.0)
            fRepathDelay = 0.5;
        
        // jitter the next repath time to spread A* load across frames
        g_fRepathTimer[entity] = fNow + random_float(fRepathDelay * 0.8, fRepathDelay * 1.2);
    }
    
    // Resolve start area
    new iStartArea = Navmesh_GetNearestAreaInternal(vStart, 500.0, 120.0);
    if(iStartArea == Invalid_Area)
        return false;
    
    // Resolve goal area if not provided / invalid
    if(iGoalArea == Invalid_Area || !IsValidAreaIndex(iGoalArea))
    {
        iGoalArea = Navmesh_GetNearestAreaInternal(vGoal, 500.0, 120.0);
        if(iGoalArea == Invalid_Area)
            return false;
    }
    
    ArrayClear(aPath);
    return BuildPathAStar(iStartArea, iGoalArea, aPath, vStart, vGoal);
}

// Advances `pathIndex` along `path` based on `vOrigin`, computes look-ahead
// `vGoalOut`, and returns NavPathResult (mirrors CCSBot::UpdatePathMovement).
public NavPathResult:native_update_path_movement(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);

    if(aPath == Invalid_Array)
        return NAV_PATH_FAILURE;
    
    new iCount = ArraySize(aPath);

    if(iCount == 0)
        return NAV_PATH_FAILURE;
    
    new iPathIndex = get_param_byref(2);

    if(iPathIndex < 0) 
        iPathIndex = 0;

    if(iPathIndex >= iCount) 
        iPathIndex = iCount - 1;
    
    new Float:vOrigin[3];
    get_array_f(3, vOrigin, 3);
    
    new Float:fAheadRange = get_param_f(5);
    new Float:fCloseEpsilon = get_param_f(6);

    if(fAheadRange <= 0.0) 
        fAheadRange = 300.0;

    if(fCloseEpsilon <= 0.0) 
        fCloseEpsilon = 20.0;
    
    // End-of-path check
    new sLast[NavPathSegment];
    ArrayGetArray(aPath, iCount - 1, sLast);
    new Float:fDXend = vOrigin[0] - Float:sLast[NAV_PATH_POS_X];
    new Float:fDYend = vOrigin[1] - Float:sLast[NAV_PATH_POS_Y];
    new Float:fDZend = vOrigin[2] - Float:sLast[NAV_PATH_POS_Z];
    
    if((fDXend * fDXend + fDYend * fDYend + fDZend * fDZend) < (fCloseEpsilon * fCloseEpsilon))
    {
        new Float:vGoal[3];
        vGoal[0] = Float:sLast[NAV_PATH_POS_X];
        vGoal[1] = Float:sLast[NAV_PATH_POS_Y];
        vGoal[2] = Float:sLast[NAV_PATH_POS_Z];

        set_array_f(4, vGoal, 3);
        set_param_byref(2, iCount - 1);
        return NAV_PATH_END_OF_PATH;
    }
    
    // Closest segment to bot (forward only). Tracks raw path progress.
    new iClosest = FindOurPositionOnPath(aPath, vOrigin, iPathIndex);

    if(iClosest < iPathIndex)
        iClosest = iPathIndex; // never go back

    // Compute look-ahead goal starting from the closest segment
    new Float:vGoalOut[3];
    new iAheadIdx = FindLookAheadPoint(aPath, vOrigin, iClosest, fAheadRange, vGoalOut);

    // Visibility walkback (mirrors CCSBot::FindPathPoint): if the look-ahead is
    // not visible from `vOrigin` (path turns a corner between bot and ahead),
    // step back along the path one segment at a time until a visible point is
    // found. Without this, the bot tries to walk in a straight line through a
    // wall when the path bends. Only runs if the caller passed an entity to
    // ignore in the trace.
    new iIgnoreEnt = (num_params >= 7) ? get_param(7) : 0;

    if(iIgnoreEnt > 0)
    {
        new Float:fFraction;
        new sSeg[NavPathSegment];

        // Walk back from iAheadIdx down to (but not below) iClosest.
        new iVisIdx = iAheadIdx;
        while(iVisIdx > iClosest)
        {
            engfunc(EngFunc_TraceLine, vOrigin, vGoalOut, IGNORE_MONSTERS, iIgnoreEnt, 0);
            get_tr2(0, TR_flFraction, fFraction);

            if(fFraction >= 1.0)
                break; // visible

            // Step back one segment along the path
            ArrayGetArray(aPath, (--iVisIdx), sSeg);
            vGoalOut[0] = Float:sSeg[NAV_PATH_POS_X];
            vGoalOut[1] = Float:sSeg[NAV_PATH_POS_Y];
            vGoalOut[2] = Float:sSeg[NAV_PATH_POS_Z];
        }
    }

    // iPathIndex stored back is the "next segment to reach" (closest + 1).
    // Mirrors CCSBot::m_pathIndex so callers can use path[iPathIndex].how to
    // decide HOW the bot must traverse from the previous segment to this one
    // (e.g. jump). The look-ahead point is returned via vGoalOut for movement.
    new iNextIdx = iClosest + 1;

    if(iNextIdx >= iCount)
        iNextIdx = iCount - 1;

    set_array_f(4, vGoalOut, 3);
    set_param_byref(2, iNextIdx);
    return NAV_PATH_PROGRESSING;
}

// Returns true if the bot should jump to traverse from segment iPathIndex-1
// to iPathIndex. Checks (1) explicit NAV_TRAVERSE_JUMP, (2) NAV_ATTR_JUMP
// attribute on the destination area going up, and (3) a height-step fallback.
// iPathIndex must be the "next segment to reach" (as set by Navmesh_UpdatePathMovement).
public bool:native_should_jump(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);
    if(aPath == Invalid_Array)
        return false;

    new iIdx = get_param(2);
    new iCount = ArraySize(aPath);

    if(iIdx <= 0 || iIdx >= iCount)
        return false;

    new sSeg[NavPathSegment], sPrev[NavPathSegment];
    ArrayGetArray(aPath, iIdx, sSeg);
    ArrayGetArray(aPath, iIdx - 1, sPrev);

    new Float:fZDelta = Float:sSeg[NAV_PATH_POS_Z] - Float:sPrev[NAV_PATH_POS_Z];

    // 1) Explicit jump traversal type
    if(sSeg[NAV_PATH_HOW] == NAV_TRAVERSE_JUMP)
        return true;

    // 2) Destination area marked as jump area, only when going up
    new iArea = sSeg[NAV_PATH_AREA];
    if(IsValidAreaIndex(iArea))
    {
        new sArea[NavArea];
        ArrayGetArray(g_aNavAreas, iArea, sArea);
        if((sArea[NAV_AREA_ATTRIBUTES] & NAV_ATTR_JUMP) && fZDelta > 0.0)
            return true;
    }

    // 3) Height-step fallback: noticeable step up that requires a hop
    //    (HL stepheight is 18 units; max jumpable is ~64). This fires even
    //    when the .nav file lacks NAV_ATTR_JUMP markers, which is the common
    //    case in maps not specifically authored for CSBots.
    if(fZDelta >= 18.0 && fZDelta <= 64.0)
        return true;

    return false;
}

// Returns the index of the path segment closest to `vOrigin`, scanning forward
// from `iStartIdx`. Used to advance pathIndex without going backwards.
//
// The scan is limited to a small window ahead of iStartIdx (mirrors CCSBot's
// "local" window in FindOurPositionOnPath). Without this, a path that bends
// back near itself (U-turn around a wall) makes a far-future segment look
// geometrically closer to the bot than the one it is actually traversing,
// so the bot teleports its progress to the other side of the U-turn and
// starts walking in the opposite direction.
FindOurPositionOnPath(Array:aPath, const Float:vOrigin[3], iStartIdx)
{
    new iCount = ArraySize(aPath);

    if(iCount == 0) 
        return 0;

    if(iStartIdx < 0) 
        iStartIdx = 0;

    if(iStartIdx >= iCount) 
        return iCount - 1;

    // Look at most this many segments forward (CSBot uses ~3).
    new const SEARCH_WINDOW = 3;
    new iEnd = iStartIdx + SEARCH_WINDOW + 1;

    if(iEnd > iCount) 
        iEnd = iCount;

    new iBestIdx = iStartIdx;
    new Float:fBestDistSq = 1.0e30;
    new sSeg[NavPathSegment];

    for(new i = iStartIdx; i < iEnd; i++)
    {
        ArrayGetArray(aPath, i, sSeg);

        new Float:fDX = vOrigin[0] - Float:sSeg[NAV_PATH_POS_X];
        new Float:fDY = vOrigin[1] - Float:sSeg[NAV_PATH_POS_Y];
        new Float:fDZ = vOrigin[2] - Float:sSeg[NAV_PATH_POS_Z];
        new Float:fDistSq = fDX * fDX + fDY * fDY + fDZ * fDZ;

        if(fDistSq < fBestDistSq)
        {
            fBestDistSq = fDistSq;
            iBestIdx = i;
        }
    }
    return iBestIdx;
}

// Walks forward from iStartIdx accumulating segment lengths until reaching
// fAheadRange from `vOrigin`. Writes the interpolated position to vGoalOut and
// returns the segment index reached. Mirrors CCSBot::FindPathPoint stop-conditions:
//   - break if a future segment doubles back vs initDir (U-turn around walls)
//   - break if the next segment turns a sharp corner (>~60deg vs prevDir)
// Without these, the look-ahead jumps across U-turns/corners and the bot
// walks in the opposite direction of the path it should be following.
FindLookAheadPoint(Array:aPath, const Float:vOrigin[3], iStartIdx, Float:fAheadRange, Float:vGoalOut[3])
{
    new iCount = ArraySize(aPath);

    if(iCount == 0) 
        return 0;

    // Reset
    if(iStartIdx < 0) 
        iStartIdx = 0;

    if(iStartIdx >= iCount)
    {
        new sLast[NavPathSegment];
        ArrayGetArray(aPath, iCount - 1, sLast);

        // Copy path pos
        vGoalOut[0] = Float:sLast[NAV_PATH_POS_X];
        vGoalOut[1] = Float:sLast[NAV_PATH_POS_Y];
        vGoalOut[2] = Float:sLast[NAV_PATH_POS_Z];

        return (iCount - 1);
    }

    new sFrom[NavPathSegment], sTo[NavPathSegment];
    ArrayGetArray(aPath, iStartIdx, sFrom);

    // Distance from origin to start segment
    new Float:vDir[3];
    vDir[0] = (Float:sFrom[NAV_PATH_POS_X] - vOrigin[0]);
    vDir[1] = (Float:sFrom[NAV_PATH_POS_Y] - vOrigin[1]);
    vDir[2] = (Float:sFrom[NAV_PATH_POS_Z] - vOrigin[2]);

    new Float:fAccum = floatsqroot(vDir[0] * vDir[0] + vDir[1] * vDir[1] + vDir[2] * vDir[2]);

    if(fAccum >= fAheadRange)
    {
        vGoalOut[0] = Float:sFrom[NAV_PATH_POS_X];
        vGoalOut[1] = Float:sFrom[NAV_PATH_POS_Y];
        vGoalOut[2] = Float:sFrom[NAV_PATH_POS_Z];

        return iStartIdx;
    }

    // Initial direction = direction of the segment leading into iStartIdx
    // (i.e. seg[iStartIdx-1] -> seg[iStartIdx]). If iStartIdx == 0, fall back
    // to bot -> seg[0]. Used to detect doubleback in the forward walk.
    new Float:vInitDir[2], Float:fInitLen;

    if(iStartIdx > 0)
    {
        new sPrev[NavPathSegment];
        ArrayGetArray(aPath, iStartIdx - 1, sPrev);

        vInitDir[0] = Float:sFrom[NAV_PATH_POS_X] - Float:sPrev[NAV_PATH_POS_X];
        vInitDir[1] = Float:sFrom[NAV_PATH_POS_Y] - Float:sPrev[NAV_PATH_POS_Y];
    }
    else
    {
        vInitDir[0] = Float:sFrom[NAV_PATH_POS_X] - vOrigin[0];
        vInitDir[1] = Float:sFrom[NAV_PATH_POS_Y] - vOrigin[1];
    }

    fInitLen = floatsqroot(vInitDir[0] * vInitDir[0] + vInitDir[1] * vInitDir[1]);

    if(fInitLen > 0.0)
    {
        vInitDir[0] /= fInitLen;
        vInitDir[1] /= fInitLen;
    }

    new Float:vPrevDir[2];
    vPrevDir[0] = vInitDir[0];
    vPrevDir[1] = vInitDir[1];

    // Walk forward summing segment lengths
    for(new i = iStartIdx; i + 1 < iCount; i++)
    {
        ArrayGetArray(aPath, i, sFrom);
        ArrayGetArray(aPath, i + 1, sTo);

        new Float:fSegDX = Float:sTo[NAV_PATH_POS_X] - Float:sFrom[NAV_PATH_POS_X];
        new Float:fSegDY = Float:sTo[NAV_PATH_POS_Y] - Float:sFrom[NAV_PATH_POS_Y];
        new Float:fSegDZ = Float:sTo[NAV_PATH_POS_Z] - Float:sFrom[NAV_PATH_POS_Z];

        // 2D direction of this segment for stop-condition checks
        new Float:fSegLen   = floatsqroot(fSegDX * fSegDX + fSegDY * fSegDY + fSegDZ * fSegDZ);
        new Float:fSegLen2D = floatsqroot(fSegDX * fSegDX + fSegDY * fSegDY);

        if(fSegLen2D > 0.0 && fInitLen > 0.0)
        {
            new Float:vCurDir[2];
            vCurDir[0] = fSegDX / fSegLen2D;
            vCurDir[1] = fSegDY / fSegLen2D;

            new Float:fDotInit = vCurDir[0] * vInitDir[0] + vCurDir[1] * vInitDir[1];
            new Float:fDotPrev = vCurDir[0] * vPrevDir[0] + vCurDir[1] * vPrevDir[1];

            // Doubleback or Sharp corner
            if(fDotInit < 0.0 || fDotPrev < 0.5)
            {
                vGoalOut[0] = Float:sFrom[NAV_PATH_POS_X];
                vGoalOut[1] = Float:sFrom[NAV_PATH_POS_Y];
                vGoalOut[2] = Float:sFrom[NAV_PATH_POS_Z];
                return i;
            }

            vPrevDir[0] = vCurDir[0];
            vPrevDir[1] = vCurDir[1];
        }

        if(fAccum + fSegLen >= fAheadRange)
        {
            new Float:fT = (fSegLen > 0.0) ? ((fAheadRange - fAccum) / fSegLen) : 0.0;

            vGoalOut[0] = Float:sFrom[NAV_PATH_POS_X] + fT * fSegDX;
            vGoalOut[1] = Float:sFrom[NAV_PATH_POS_Y] + fT * fSegDY;
            vGoalOut[2] = Float:sFrom[NAV_PATH_POS_Z] + fT * fSegDZ;
            return i + 1;
        }

        fAccum += fSegLen;
    }

    // Exhausted path: clamp to last
    new sLast[NavPathSegment];
    ArrayGetArray(aPath, iCount - 1, sLast);

    vGoalOut[0] = Float:sLast[NAV_PATH_POS_X];
    vGoalOut[1] = Float:sLast[NAV_PATH_POS_Y];
    vGoalOut[2] = Float:sLast[NAV_PATH_POS_Z];

    return iCount - 1;
}

// ----------------------------------------------------------------------------
// Path utility natives (mirror CNavPath helpers from ReGameDLL_CS)
// ----------------------------------------------------------------------------

public Float:native_get_path_distance(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);

    if(aPath == Invalid_Array)
        return 0.0;

    return GetPathTotalDistance(aPath);
}

public bool:native_is_at_end_of_path(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);

    if(aPath == Invalid_Array || ArraySize(aPath) == 0)
        return false;
    
    new Float:vPos[3];
    get_array_f(2, vPos, 3);

    new Float:fEpsilon = get_param_f(3);

    if(fEpsilon <= 0.0)
        fEpsilon = 20.0;
    
    new sSeg[NavPathSegment];
    ArrayGetArray(aPath, ArraySize(aPath) - 1, sSeg);
    
    new Float:fDX = vPos[0] - Float:sSeg[NAV_PATH_POS_X];
    new Float:fDY = vPos[1] - Float:sSeg[NAV_PATH_POS_Y];
    new Float:fDZ = vPos[2] - Float:sSeg[NAV_PATH_POS_Z];
    
    return (fDX * fDX + fDY * fDY + fDZ * fDZ) < (fEpsilon * fEpsilon);
}

public bool:native_get_point_along_path(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);
    new Float:fDistAlong = get_param_f(2);
    
    if(aPath == Invalid_Array)
        return false;
    
    new iCount = ArraySize(aPath);

    if(iCount == 0)
        return false;
    
    new Float:vPoint[3];
    new sSeg[NavPathSegment];
    
    if(fDistAlong <= 0.0)
    {
        ArrayGetArray(aPath, 0, sSeg);

        vPoint[0] = Float:sSeg[NAV_PATH_POS_X];
        vPoint[1] = Float:sSeg[NAV_PATH_POS_Y];
        vPoint[2] = Float:sSeg[NAV_PATH_POS_Z];

        set_array_f(3, vPoint, 3);
        return true;
    }
    
    new Float:fLengthSoFar;
    new sPrev[NavPathSegment];
    ArrayGetArray(aPath, 0, sPrev);
    
    for(new i = 1; i < iCount; i++)
    {
        ArrayGetArray(aPath, i, sSeg);
        
        new Float:fDX = Float:sSeg[NAV_PATH_POS_X] - Float:sPrev[NAV_PATH_POS_X];
        new Float:fDY = Float:sSeg[NAV_PATH_POS_Y] - Float:sPrev[NAV_PATH_POS_Y];
        new Float:fDZ = Float:sSeg[NAV_PATH_POS_Z] - Float:sPrev[NAV_PATH_POS_Z];

        new Float:fSegLen = floatsqroot(fDX * fDX + fDY * fDY + fDZ * fDZ);
        if(fSegLen + fLengthSoFar >= fDistAlong)
        {
            new Float:fDelta = fDistAlong - fLengthSoFar;
            new Float:fT = (fSegLen > 0.0) ? (fDelta / fSegLen) : 0.0;
            
            vPoint[0] = Float:sPrev[NAV_PATH_POS_X] + fT * fDX;
            vPoint[1] = Float:sPrev[NAV_PATH_POS_Y] + fT * fDY;
            vPoint[2] = Float:sPrev[NAV_PATH_POS_Z] + fT * fDZ;

            set_array_f(3, vPoint, 3);
            return true;
        }
        
        fLengthSoFar += fSegLen;
        sPrev = sSeg;
    }
    
    // Past the end - clamp to last segment
    ArrayGetArray(aPath, iCount - 1, sSeg);

    vPoint[0] = Float:sSeg[NAV_PATH_POS_X];
    vPoint[1] = Float:sSeg[NAV_PATH_POS_Y];
    vPoint[2] = Float:sSeg[NAV_PATH_POS_Z];

    set_array_f(3, vPoint, 3);
    return true;
}

public native_get_segment_index_along_path(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);
    new Float:fDistAlong = get_param_f(2);
    
    if(aPath == Invalid_Array)
        return -1;
    
    new iCount = ArraySize(aPath);

    if(iCount == 0)
        return -1;
    
    if(fDistAlong <= 0.0)
        return 0;
    
    new Float:fLengthSoFar = 0.0;
    new sPrev[NavPathSegment], sSeg[NavPathSegment];
    ArrayGetArray(aPath, 0, sPrev);
    
    for(new i = 1; i < iCount; i++)
    {
        ArrayGetArray(aPath, i, sSeg);
        
        new Float:fDX = Float:sSeg[NAV_PATH_POS_X] - Float:sPrev[NAV_PATH_POS_X];
        new Float:fDY = Float:sSeg[NAV_PATH_POS_Y] - Float:sPrev[NAV_PATH_POS_Y];
        new Float:fDZ = Float:sSeg[NAV_PATH_POS_Z] - Float:sPrev[NAV_PATH_POS_Z];

        fLengthSoFar += floatsqroot(fDX * fDX + fDY * fDY + fDZ * fDZ);
        
        if(fLengthSoFar > fDistAlong)
            return i - 1;
        
        sPrev = sSeg;
    }
    
    return iCount - 1;
}

public bool:native_find_closest_point_on_path(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);

    if(aPath == Invalid_Array)
        return false;
    
    new iCount = ArraySize(aPath);

    if(iCount < 2)
        return false;
    
    new Float:vWorld[3];
    get_array_f(2, vWorld, 3);

    new iStart  = get_param(3);
    new iEnd    = get_param(4);
    
    if(iStart < 1) 
        iStart = 1;

    if(iEnd >= iCount) 
        iEnd = iCount - 1;

    if(iStart > iEnd) 
        return false;
    
    new Float:vClose[3];
    new Float:fCloseDistSq = 9999999999.9;
    new sFrom[NavPathSegment], sTo[NavPathSegment];
    
    for(new i = iStart; i <= iEnd; i++)
    {
        ArrayGetArray(aPath, i - 1, sFrom);
        ArrayGetArray(aPath, i, sTo);
        
        new Float:vAlong[3];
        vAlong[0] = Float:sTo[NAV_PATH_POS_X] - Float:sFrom[NAV_PATH_POS_X];
        vAlong[1] = Float:sTo[NAV_PATH_POS_Y] - Float:sFrom[NAV_PATH_POS_Y];
        vAlong[2] = Float:sTo[NAV_PATH_POS_Z] - Float:sFrom[NAV_PATH_POS_Z];
        
        new Float:fLen = floatsqroot(vAlong[0] * vAlong[0] + vAlong[1] * vAlong[1] + vAlong[2] * vAlong[2]);
        if(fLen <= 0.0)
            continue;
        
        new Float:fInv = 1.0 / fLen;
        vAlong[0] *= fInv;
        vAlong[1] *= fInv;
        vAlong[2] *= fInv;
        
        new Float:vToWorld[3];
        vToWorld[0] = vWorld[0] - Float:sFrom[NAV_PATH_POS_X];
        vToWorld[1] = vWorld[1] - Float:sFrom[NAV_PATH_POS_Y];
        vToWorld[2] = vWorld[2] - Float:sFrom[NAV_PATH_POS_Z];
        
        new Float:fCloseLen = vToWorld[0] * vAlong[0] + vToWorld[1] * vAlong[1] + vToWorld[2] * vAlong[2];
        new Float:vPos[3];
        
        if(fCloseLen <= 0.0)
        {
            vPos[0] = Float:sFrom[NAV_PATH_POS_X];
            vPos[1] = Float:sFrom[NAV_PATH_POS_Y];
            vPos[2] = Float:sFrom[NAV_PATH_POS_Z];
        }
        else if(fCloseLen >= fLen)
        {
            vPos[0] = Float:sTo[NAV_PATH_POS_X];
            vPos[1] = Float:sTo[NAV_PATH_POS_Y];
            vPos[2] = Float:sTo[NAV_PATH_POS_Z];
        }
        else
        {
            vPos[0] = Float:sFrom[NAV_PATH_POS_X] + fCloseLen * vAlong[0];
            vPos[1] = Float:sFrom[NAV_PATH_POS_Y] + fCloseLen * vAlong[1];
            vPos[2] = Float:sFrom[NAV_PATH_POS_Z] + fCloseLen * vAlong[2];
        }
        
        new Float:fDX = vPos[0] - vWorld[0];
        new Float:fDY = vPos[1] - vWorld[1];
        new Float:fDZ = vPos[2] - vWorld[2];
        new Float:fDistSq = fDX * fDX + fDY * fDY + fDZ * fDZ;
        
        if(fDistSq < fCloseDistSq)
        {
            fCloseDistSq = fDistSq;
            vClose = vPos;
        }
    }
    
    set_array_f(5, vClose, 3);
    return true;
}

public Float:native_travel_distance(plugin_id, num_params)
{
    new iStartArea = get_param(1);
    new iGoalArea = get_param(2);
    
    if(!IsValidAreaIndex(iStartArea) || !IsValidAreaIndex(iGoalArea))
        return -1.0;
    
    if(iStartArea == iGoalArea)
        return 0.0;
    
    new Array:aPath = ArrayCreate(NavPathSegment);
    
    // No specific positions for this area-only API; use area centers.
    new sStart[NavArea], sGoal[NavArea];
    ArrayGetArray(g_aNavAreas, iStartArea, sStart);
    ArrayGetArray(g_aNavAreas, iGoalArea, sGoal);

    new Float:vStart[3], Float:vGoal[3];
    vStart[0] = Float:sStart[NAV_AREA_CENTER_X];
    vStart[1] = Float:sStart[NAV_AREA_CENTER_Y];
    vStart[2] = Float:sStart[NAV_AREA_CENTER_Z];

    vGoal[0] = Float:sGoal[NAV_AREA_CENTER_X];
    vGoal[1] = Float:sGoal[NAV_AREA_CENTER_Y];
    vGoal[2] = Float:sGoal[NAV_AREA_CENTER_Z];
    
    new bool:bFound = BuildPathAStar(iStartArea, iGoalArea, aPath, vStart, vGoal);
    
    if(!bFound)
    {
        ArrayDestroy(aPath);
        return -1.0;
    }
    
    new Float:fDist = GetPathTotalDistance(aPath);
    ArrayDestroy(aPath);
    return fDist;
}

// Helper: total length walking from segment to segment (mirrors CNavPath::GetLength)
Float:GetPathTotalDistance(Array:aPath)
{
    new iCount = ArraySize(aPath);
    if(iCount < 2)
        return 0.0;
    
    new Float:fLength = 0.0;
    new sPrev[NavPathSegment], sSeg[NavPathSegment];
    ArrayGetArray(aPath, 0, sPrev);
    
    for(new i = 1; i < iCount; i++)
    {
        ArrayGetArray(aPath, i, sSeg);

        new Float:fDX = Float:sSeg[NAV_PATH_POS_X] - Float:sPrev[NAV_PATH_POS_X];
        new Float:fDY = Float:sSeg[NAV_PATH_POS_Y] - Float:sPrev[NAV_PATH_POS_Y];
        new Float:fDZ = Float:sSeg[NAV_PATH_POS_Z] - Float:sPrev[NAV_PATH_POS_Z];

        fLength += floatsqroot(fDX * fDX + fDY * fDY + fDZ * fDZ);
        sPrev = sSeg;
    }
    
    return fLength;
}

// ----------------------------------------------------------------------------
// Path optimization (line-of-sight smoothing) - mirrors CNavPath::Optimize.
// Removes redundant nodes whose between-line is unobstructed.
// Ladder segments are kept as anchors so we don't cut through them.
// ----------------------------------------------------------------------------
public native_optimize_path(plugin_id, num_params)
{
    new Array:aPath = Array:get_param(1);
    new iIgnoreEnt = get_param(2);
    
    if(aPath == Invalid_Array)
        return 0;
    
    new iCount = ArraySize(aPath);
    
    if(iCount < 3)
        return iCount;
    
    new iAnchor = 0;

    while(iAnchor < ArraySize(aPath))
    {
        new iOccluded = FindNextOccludedNode(aPath, iAnchor, iIgnoreEnt);
        new iNextAnchor = iOccluded - 1;
        
        if(iNextAnchor > iAnchor)
        {
            new iRemoveCount = iNextAnchor - iAnchor - 1;

            if(iRemoveCount > 0)
            {
                // Delete segments [iAnchor+1 .. iNextAnchor-1]
                for(new k = 0; k < iRemoveCount; k++)
                    ArrayDeleteItem(aPath, iAnchor + 1);
            }
        }
        
        iAnchor++;
    }
    
    return ArraySize(aPath);
}

// Returns the index of the next node not visible from anchor (or path end).
// Always stops at ladder nodes (mirrors CNavPath::FindNextOccludedNode).
FindNextOccludedNode(Array:aPath, iAnchor, iIgnoreEnt)
{
    new iCount = ArraySize(aPath);
    new sAnchor[NavPathSegment], sSeg[NavPathSegment];
    ArrayGetArray(aPath, iAnchor, sAnchor);
    
    new Float:vAnchor[3];
    vAnchor[0] = Float:sAnchor[NAV_PATH_POS_X];
    vAnchor[1] = Float:sAnchor[NAV_PATH_POS_Y];
    vAnchor[2] = Float:sAnchor[NAV_PATH_POS_Z];
    
    for(new i = iAnchor + 1; i < iCount; i++)
    {
        ArrayGetArray(aPath, i, sSeg);
        
        // Don't optimize across ladder segments
        if(sSeg[NAV_PATH_HOW] == NAV_TRAVERSE_LADDER_UP || sSeg[NAV_PATH_HOW] == NAV_TRAVERSE_LADDER_DOWN)
            return i;
        
        new Float:vEnd[3];
        vEnd[0] = Float:sSeg[NAV_PATH_POS_X];
        vEnd[1] = Float:sSeg[NAV_PATH_POS_Y];
        vEnd[2] = Float:sSeg[NAV_PATH_POS_Z];
        
        if(!IsWalkableTraceLineClear(vAnchor, vEnd, iIgnoreEnt))
            return i;
        
        // Also check at half-human and full-human heights
        new Float:vAnchorMid[3], Float:vEndMid[3];
        vAnchorMid[0] = vAnchor[0]; 
        vAnchorMid[1] = vAnchor[1]; 
        vAnchorMid[2] = vAnchor[2] + HALF_HUMAN_HEIGHT;

        vEndMid[0] = vEnd[0];    
        vEndMid[1] = vEnd[1];    
        vEndMid[2] = vEnd[2] + HALF_HUMAN_HEIGHT;

        if(!IsWalkableTraceLineClear(vAnchorMid, vEndMid, iIgnoreEnt))
            return i;
        
        new Float:vAnchorTop[3], Float:vEndTop[3];
        vAnchorTop[0] = vAnchor[0]; 
        vAnchorTop[1] = vAnchor[1]; 
        vAnchorTop[2] = vAnchor[2] + HUMAN_HEIGHT;

        vEndTop[0] = vEnd[0];
        vEndTop[1] = vEnd[1];    
        vEndTop[2] = vEnd[2] + HUMAN_HEIGHT;

        if(!IsWalkableTraceLineClear(vAnchorTop, vEndTop, iIgnoreEnt))
            return i;
    }
    
    return iCount;
}

// Walkable trace: world + monsters/players blocked, hostage-style.
// Returns true if the trace from vStart to vEnd is unobstructed.
bool:IsWalkableTraceLineClear(const Float:vStart[3], const Float:vEnd[3], iIgnoreEnt)
{
    new iTrace = create_tr2();
    engfunc(EngFunc_TraceLine, vStart, vEnd, IGNORE_MONSTERS, iIgnoreEnt, iTrace);
    
    new Float:fFraction;
    get_tr2(iTrace, TR_flFraction, fFraction);
    free_tr2(iTrace);
    
    return fFraction >= 1.0;
}

// ============================================================================
// Natives - Utilities
// ============================================================================

public bool:native_get_closest_point_in_area(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new Float:vPos[3], Float:vClose[3];
    get_array_f(2, vPos, 3);
    
    GetClosestPointInArea(iAreaIndex, vPos, vClose);
    
    set_array_f(3, vClose, 3);
    return true;
}

public Float:native_get_distance_squared_to_area(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return 0.0;
    
    new Float:vPos[3];
    get_array_f(2, vPos, 3);
    
    return GetDistanceSquaredToArea(iAreaIndex, vPos);
}

public native_get_random_area(plugin_id, num_params)
{
    if(!g_bNavLoaded || g_iNavAreaCount == 0)
        return Invalid_Area;
    
    return random_num(0, g_iNavAreaCount - 1);
}

public bool:native_get_random_position_in_area(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new Float:vPos[3];
    GetRandomPositionInArea(iAreaIndex, vPos);
    
    set_array_f(2, vPos, 3);
    return true;
}

// ============================================================================
// Natives - Additional Functions
// ============================================================================

public bool:native_get_area_corner(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new NavCornerType:corner = NavCornerType:get_param(2);
    
    if(!IsValidAreaIndex(iAreaIndex) || corner >= NUM_NAV_CORNERS)
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:vPos[3];
    GetAreaCorner(sArea, corner, vPos);
    
    set_array_f(3, vPos, 3);
    return true;
}

public bool:native_is_area_overlapping(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new Float:vPos[3];
    get_array_f(2, vPos, 3);
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    return IsOverlappingPoint(sArea, vPos);
}

public bool:native_are_areas_overlapping(plugin_id, num_params)
{
    new iAreaIndex1 = get_param(1);
    new iAreaIndex2 = get_param(2);
    
    if(!IsValidAreaIndex(iAreaIndex1) || !IsValidAreaIndex(iAreaIndex2))
        return false;
    
    new sArea1[NavArea], sArea2[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex1, sArea1);
    ArrayGetArray(g_aNavAreas, iAreaIndex2, sArea2);
    
    return AreAreasOverlapping(sArea1, sArea2);
}

public bool:native_compute_portal(plugin_id, num_params)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidAreaIndex(iFromArea) || !IsValidAreaIndex(iToArea))
        return false;
    
    new sFrom[NavArea], sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    new Float:vCenter[3], Float:fHalfWidth;
    ComputePortal(sFrom, sTo, dir, vCenter, fHalfWidth);
    
    set_array_f(4, vCenter, 3);
    set_param_byref(5, _:fHalfWidth);
    return true;
}

public bool:native_compute_closest_point_in_portal(plugin_id, num_params)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidAreaIndex(iFromArea) || !IsValidAreaIndex(iToArea))
        return false;
    
    new Float:vFromPos[3], Float:vClosePos[3];
    get_array_f(4, vFromPos, 3);
    
    new sFrom[NavArea], sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    ComputeClosestPointInPortal(sFrom, sTo, dir, vFromPos, vClosePos);
    
    set_array_f(5, vClosePos, 3);
    return true;
}

public native_get_area_place(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return UNDEFINED_PLACE;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return sArea[NAV_AREA_PLACE];
}

public bool:native_get_place_name(plugin_id, num_params)
{
    new iPlaceID = get_param(1);
    new iMaxLen = get_param(3);
    
    if(iPlaceID <= 0 || g_nPlace[NAV_PLACE_NAMES] == Invalid_Array)
        return false;
    
    // El placeID es 1-indexed en el directorio
    new iIndex = iPlaceID - 1;
    if(iIndex < 0 || iIndex >= ArraySize(g_nPlace[NAV_PLACE_NAMES]))
        return false;
    
    new szName[32];
    ArrayGetString(g_nPlace[NAV_PLACE_NAMES], iIndex, szName, charsmax(szName));
    set_string(2, szName, iMaxLen);
    return true;
}

public native_get_approach_count(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return 0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return sArea[NAV_AREA_APPROACH_COUNT];
}

public bool:native_get_approach_info(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new iApproachIndex = get_param(2);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    if(iApproachIndex < 0 || iApproachIndex >= sArea[NAV_AREA_APPROACH_COUNT])
        return false;
    
    if(sArea[NAV_AREA_APPROACH] == Invalid_Array)
        return false;
    
    new sApproach[NavApproachInfo];
    ArrayGetArray(sArea[NAV_AREA_APPROACH], iApproachIndex, sApproach);
    
    set_param_byref(3, sApproach[NAV_APPROACH_HERE_AREA]);
    set_param_byref(4, sApproach[NAV_APPROACH_PREV_AREA]);
    set_param_byref(5, sApproach[NAV_APPROACH_NEXT_AREA]);
    set_param_byref(6, _:sApproach[NAV_APPROACH_PREV_TO_HERE_HOW]);
    set_param_byref(7, _:sApproach[NAV_APPROACH_HERE_TO_NEXT_HOW]);
    return true;
}

public native_get_ladder_count(plugin_id, num_params)
{
    if(g_aNavLadders == Invalid_Array)
        return 0;
    
    return ArraySize(g_aNavLadders);
}

public bool:native_get_ladder_info(plugin_id, num_params)
{
    new iLadderIndex = get_param(1);
    
    if(g_aNavLadders == Invalid_Array || iLadderIndex < 0 || iLadderIndex >= ArraySize(g_aNavLadders))
        return false;
    
    new sLadder[NavLadder];
    ArrayGetArray(g_aNavLadders, iLadderIndex, sLadder);
    
    new Float:vTop[3], Float:vBottom[3];

    vTop[0] = Float:sLadder[NAV_LADDER_TOP_X];
    vTop[1] = Float:sLadder[NAV_LADDER_TOP_Y];
    vTop[2] = Float:sLadder[NAV_LADDER_TOP_Z];

    vBottom[0] = Float:sLadder[NAV_LADDER_BOTTOM_X];
    vBottom[1] = Float:sLadder[NAV_LADDER_BOTTOM_Y];
    vBottom[2] = Float:sLadder[NAV_LADDER_BOTTOM_Z];
    
    set_array_f(2, vTop, 3);
    set_array_f(3, vBottom, 3);
    set_param_byref(4, _:sLadder[NAV_LADDER_LENGTH]);
    set_param_byref(5, _:sLadder[NAV_LADDER_DIR]);
    return true;
}

// ============================================================================
// Internal Functions - Loading
// ============================================================================

NavErrorType:Navmesh_LoadInternal(const szMapName[])
{
    // If already loaded, unload first
    if(g_bNavLoaded)
        Navmesh_UnloadInternal();
    
    // Build file path
    new szFilePath[128];
    formatex(szFilePath, charsmax(szFilePath), "maps/%s.nav", szMapName);
    
    if(!file_exists(szFilePath))
    {
        log_amx("[NavMesh] File not found: %s", szFilePath);
        return NAV_CANT_ACCESS_FILE;
    }
    
    // Open file
    new iFile = fopen(szFilePath, "rb");
    if(!iFile)
    {
        log_amx("[NavMesh] Cannot open file: %s", szFilePath);
        return NAV_CANT_ACCESS_FILE;
    }
    
    // Read and verify magic number
    new iMagic;
    if(!FileReadInt32(iFile, iMagic) || iMagic != NAV_MAGIC_NUMBER)
    {
        log_amx("[NavMesh] Invalid magic number");
        fclose(iFile);
        return NAV_INVALID_FILE;
    }
    
    // Read version
    new iVersion;
    if(!FileReadInt32(iFile, iVersion) || iVersion > NAV_VERSION)
    {
        log_amx("[NavMesh] Unsupported version %d (max %d)", iVersion, NAV_VERSION);
        fclose(iFile);
        return NAV_BAD_FILE_VERSION;
    }
    
    // Initialize arrays
    g_aNavAreas = ArrayCreate(NavArea);
    g_aNavLadders = ArrayCreate(NavLadder);
    
    // Skip BSP size (version >= 4)
    if(iVersion >= 4)
        fseek(iFile, BLOCK_INT, SEEK_CUR);
    
    // Load place directory (version >= 5)
    if(iVersion >= NAV_VERSION)
    {
        if(!LoadPlaceDirectory(iFile))
        {
            log_amx("[NavMesh] Failed to load place directory");

            fclose(iFile);
            Navmesh_UnloadInternal();
            return NAV_CORRUPT_DATA;
        }
    }
    
    // Read area count
    if(!FileReadInt32(iFile, g_iNavAreaCount))
    {
        log_amx("[NavMesh] Failed to read area count");

        fclose(iFile);
        Navmesh_UnloadInternal();
        return NAV_CORRUPT_DATA;
    }
    
    if(g_iNavAreaCount == 0)
    {
        log_amx("[NavMesh] No areas in file");

        fclose(iFile);
        Navmesh_UnloadInternal();
        return NAV_INVALID_FILE;
    }
    
    // Load areas and calculate total extent
    new Float:fMinX = 999999.9, Float:fMinY = 999999.9;
    new Float:fMaxX = -999999.9, Float:fMaxY = -999999.9;
    
    for(new i = 0; i < g_iNavAreaCount; i++)
    {
        if(!LoadArea(iFile, iVersion))
        {
            log_amx("[NavMesh] Failed to load area %d", i);
            fclose(iFile);

            Navmesh_UnloadInternal();
            return NAV_CORRUPT_DATA;
        }
        
        // Update total extent
        new sArea[NavArea];
        ArrayGetArray(g_aNavAreas, i, sArea);
        
        if(Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] < fMinX)
            fMinX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
        if(Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] < fMinY)
            fMinY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
        if(Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X] > fMaxX)
            fMaxX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
        if(Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y] > fMaxY)
            fMaxY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    }
    
    fclose(iFile);
    
    // Initialize grid
    InitGrid(fMinX, fMaxX, fMinY, fMaxY);
    
    // Add areas to grid
    for(new i = 0; i < g_iNavAreaCount; i++)
        AddAreaToGrid(i);
    
    // Mark as loaded BEFORE resolving connections
    // (FindAreaByID requires g_bNavLoaded = true)
    g_bNavLoaded = true;
    
    // Post-load: resolve connections
    for(new i = 0; i < g_iNavAreaCount; i++)
        PostLoadArea(i);
    
    log_amx("[NavMesh] Loaded successfully: %d areas", g_iNavAreaCount);
    return NAV_OK;
}

Navmesh_UnloadInternal()
{
    if(!g_bNavLoaded)
        return;
    
    // Free connection arrays for each area
    if(g_aNavAreas != Invalid_Array)
    {
        new sArea[NavArea];
        for(new i = 0; i < g_iNavAreaCount; i++)
        {
            ArrayGetArray(g_aNavAreas, i, sArea);
            
            if(sArea[NAV_AREA_CONNECT_NORTH] != Invalid_Array)
                ArrayDestroy(sArea[NAV_AREA_CONNECT_NORTH]);
            if(sArea[NAV_AREA_CONNECT_EAST] != Invalid_Array)
                ArrayDestroy(sArea[NAV_AREA_CONNECT_EAST]);
            if(sArea[NAV_AREA_CONNECT_SOUTH] != Invalid_Array)
                ArrayDestroy(sArea[NAV_AREA_CONNECT_SOUTH]);
            if(sArea[NAV_AREA_CONNECT_WEST] != Invalid_Array)
                ArrayDestroy(sArea[NAV_AREA_CONNECT_WEST]);
            if(sArea[NAV_AREA_APPROACH] != Invalid_Array)
                ArrayDestroy(sArea[NAV_AREA_APPROACH]);
        }
        
        ArrayDestroy(g_aNavAreas);
        g_aNavAreas = Invalid_Array;
    }
    
    if(g_aNavLadders != Invalid_Array)
    {
        ArrayDestroy(g_aNavLadders);
        g_aNavLadders = Invalid_Array;
    }
    
    // Free grid
    if(g_nGrid[NAV_GRID_CELLS] != Invalid_Array)
    {
        ArrayDestroy(g_nGrid[NAV_GRID_CELLS]);
        g_nGrid[NAV_GRID_CELLS] = Invalid_Array;
    }
    
    // Free place directory
    if(g_nPlace[NAV_PLACE_NAMES] != Invalid_Array)
    {
        ArrayDestroy(g_nPlace[NAV_PLACE_NAMES]);
        g_nPlace[NAV_PLACE_NAMES] = Invalid_Array;
    }
    if(g_nPlace[NAV_PLACE_IDS] != Invalid_Array)
    {
        ArrayDestroy(g_nPlace[NAV_PLACE_IDS]);
        g_nPlace[NAV_PLACE_IDS] = Invalid_Array;
    }
    
    g_bNavLoaded = false;
    g_iNavAreaCount = 0;
    g_iNextAreaID = 1;
}

bool:Navmesh_InitEmpty()
{
    // If navmesh already loaded, unload first
    if(g_bNavLoaded)
        Navmesh_UnloadInternal();
    
    // Create empty arrays
    g_aNavAreas = ArrayCreate(NavArea);
    g_aNavLadders = ArrayCreate(NavLadder);
    
    // Initialize empty place directory
    g_nPlace[NAV_PLACE_NAMES] = ArrayCreate(32);
    g_nPlace[NAV_PLACE_IDS] = ArrayCreate();
    g_nPlace[NAV_PLACE_COUNT] = 0;
    
    // Initialize grid with default values (typical CS map)
    InitGrid(-4096.0, 4096.0, -4096.0, 4096.0);
    
    g_iNavAreaCount = 0;
    g_iNextAreaID = 1;
    g_bNavLoaded = true;
    
    log_amx("[NavMesh] Initialized empty navmesh for editing");
    return true;
}

// ============================================================================
// Internal Functions - Data Loading
// ============================================================================

bool:LoadPlaceDirectory(iFile)
{
    new iPlaceCount;
    if(!FileReadUint16(iFile, iPlaceCount))
        return false;
    
    g_nPlace[NAV_PLACE_NAMES] = ArrayCreate(32);
    g_nPlace[NAV_PLACE_IDS] = ArrayCreate();
    g_nPlace[NAV_PLACE_COUNT] = iPlaceCount;
    
    for(new i = 0; i < iPlaceCount; i++)
    {
        new iLen;
        if(!FileReadUint16(iFile, iLen))
            return false;
        
        new szPlaceName[32];
        fread_blocks(iFile, szPlaceName, iLen, BLOCK_BYTE);
        
        ArrayPushString(g_nPlace[NAV_PLACE_NAMES], szPlaceName);
        ArrayPushCell(g_nPlace[NAV_PLACE_IDS], i + 1);
    }
    
    return true;
}

bool:LoadArea(iFile, iVersion)
{
    new sArea[NavArea];
    
    // Read ID
    if(!FileReadInt32(iFile, sArea[NAV_AREA_ID]))
        return false;
    
    if(sArea[NAV_AREA_ID] >= g_iNextAreaID)
        g_iNextAreaID = sArea[NAV_AREA_ID] + 1;
    
    // Read attributes
    new iAttr;
    if(!FileReadUint8(iFile, iAttr))
        return false;

    sArea[NAV_AREA_ATTRIBUTES] = NavAttributeType:iAttr;
    
    // Read extent (6 floats)
    new Float:fTemp;
    for(new i = 0; i < 6; i++)
    {
        if(!FileReadFloat(iFile, fTemp))
            return false;
        sArea[NAV_AREA_EXTENT + i] = _:fTemp;
    }
    
    // Calculate center
    sArea[NAV_AREA_CENTER_X] = (Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] + Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X]) / 2.0;
    sArea[NAV_AREA_CENTER_Y] = (Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] + Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y]) / 2.0;
    sArea[NAV_AREA_CENTER_Z] = (Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z] + Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z]) / 2.0;
    
    // Read corner heights
    new Float:fNEZ, Float:fSWZ;
    if(!FileReadFloat(iFile, fNEZ) || !FileReadFloat(iFile, fSWZ))
        return false;
    
    sArea[NAV_AREA_NE_Z] = _:fNEZ;
    sArea[NAV_AREA_SW_Z] = _:fSWZ;
    
    // Create connection arrays
    sArea[NAV_AREA_CONNECT_NORTH]   = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_EAST]    = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_SOUTH]   = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_WEST]    = ArrayCreate(NavConnect);
    
    // Read connections for each direction
    for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
    {
        new iConnectCount;
        if(!FileReadInt32(iFile, _:iConnectCount))
            return false;
        
        new Array:aConnect = GetAreaConnectArray(sArea, dir);
        
        for(new i = 0; i < iConnectCount; i++)
        {
            new sConnect[NavConnect];
            if(!FileReadInt32(iFile, sConnect[NAV_CONNECT_ID]))
                return false;
            
            sConnect[NAV_CONNECT_AREA] = Invalid_Area; // Will be resolved in PostLoad
            ArrayPushArray(aConnect, sConnect);
        }
    }
    
    // Skip hiding spots
    new iHidingSpotCount;
    if(!FileReadUint8(iFile, iHidingSpotCount))
        return false;
    
    for(new i = 0; i < iHidingSpotCount; i++)
    {
        // Skip: ID (4) + pos (12) + flags (1) = 17 bytes
        fseek(iFile, 17, SEEK_CUR);
    }
    
    // Read approach areas
    if(!FileReadUint8(iFile, sArea[NAV_AREA_APPROACH_COUNT]))
        return false;
    
    sArea[NAV_AREA_APPROACH] = ArrayCreate(NavApproachInfo);
    
    for(new i = 0; i < sArea[NAV_AREA_APPROACH_COUNT]; i++)
    {
        new sApproach[NavApproachInfo];
        
        if(!FileReadInt32(iFile, sApproach[NAV_APPROACH_HERE_ID]) || !FileReadInt32(iFile, sApproach[NAV_APPROACH_PREV_ID]))
            return false;
        
        new iType;
        if(!FileReadUint8(iFile, iType))
            return false;

        sApproach[NAV_APPROACH_PREV_TO_HERE_HOW] = NavTraverseType:iType;
        
        if(!FileReadInt32(iFile, sApproach[NAV_APPROACH_NEXT_ID]) || !FileReadUint8(iFile, iType))
            return false;

        sApproach[NAV_APPROACH_HERE_TO_NEXT_HOW] = NavTraverseType:iType;
        ArrayPushArray(sArea[NAV_AREA_APPROACH], sApproach);
    }
    
    // Skip encounter spots
    new iEncounterCount;
    if(!FileReadInt32(iFile, iEncounterCount))
        return false;
    
    for(new i = 0; i < iEncounterCount; i++)
    {
        // Skip: from ID (4) + from dir (1) + to ID (4) + to dir (1) = 10 bytes
        fseek(iFile, 10, SEEK_CUR);
        
        new iSpotCount;
        if(!FileReadUint8(iFile, iSpotCount))
            return false;
        
        // Skip spots: each is ID (4) + t (1) = 5 bytes
        fseek(iFile, iSpotCount * 5, SEEK_CUR);
    }
    
    // Read place (version >= 5)
    if(iVersion >= NAV_VERSION)
    {
        new iPlaceEntry;
        if(!FileReadUint16(iFile, iPlaceEntry))
            return false;

        sArea[NAV_AREA_PLACE] = iPlaceEntry;
    }
    
    // Initialize pathfinding variables
    sArea[NAV_AREA_TOTAL_COST] = 0.0;
    sArea[NAV_AREA_COST_SO_FAR] = 0.0;
    sArea[NAV_AREA_PARENT] = Invalid_Area;
    sArea[NAV_AREA_PARENT_HOW] = NAV_TRAVERSE_NORTH;
    sArea[NAV_AREA_MARKER] = 0;
    sArea[NAV_AREA_OPEN_MARKER] = 0;
    sArea[NAV_AREA_PREV_HASH] = Invalid_Area;
    sArea[NAV_AREA_NEXT_HASH] = Invalid_Area;
    
    ArrayPushArray(g_aNavAreas, sArea);
    return true;
}

bool:PostLoadArea(iAreaIndex)
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    // Resolve connections
    for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
    {
        new Array:aConnect = GetAreaConnectArray(sArea, dir);
        if(aConnect == Invalid_Array)
            continue;
        
        for(new i = 0; i < ArraySize(aConnect); i++)
        {
            new sConnect[NavConnect];
            ArrayGetArray(aConnect, i, sConnect);
            
            // Find area by ID
            new iConnectAreaIndex = FindAreaByID(sConnect[NAV_CONNECT_ID]);
            if(iConnectAreaIndex == Invalid_Area)
            {
                log_amx("[NavMesh] Warning: Area %d has invalid connection to ID %d", 
                    sArea[NAV_AREA_ID], sConnect[NAV_CONNECT_ID]);
                continue;
            }
            
            sConnect[NAV_CONNECT_AREA] = iConnectAreaIndex;
            ArraySetArray(aConnect, i, sConnect);
        }
    }
    
    // Resolver approach areas
    for(new i = 0; i < sArea[NAV_AREA_APPROACH_COUNT]; i++)
    {
        new sApproach[NavApproachInfo];
        ArrayGetArray(sArea[NAV_AREA_APPROACH], i, sApproach);
        
        sApproach[NAV_APPROACH_HERE_AREA] = FindAreaByID(sApproach[NAV_APPROACH_HERE_ID]);
        sApproach[NAV_APPROACH_PREV_AREA] = FindAreaByID(sApproach[NAV_APPROACH_PREV_ID]);
        sApproach[NAV_APPROACH_NEXT_AREA] = FindAreaByID(sApproach[NAV_APPROACH_NEXT_ID]);
        
        ArraySetArray(sArea[NAV_AREA_APPROACH], i, sApproach);
    }
    
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    return true;
}

// ============================================================================
// Internal Functions - Grid
// ============================================================================

InitGrid(Float:fMinX, Float:fMaxX, Float:fMinY, Float:fMaxY)
{
    g_nGrid[NAV_GRID_CELL_SIZE] = _:GRID_CELL_SIZE;
    g_nGrid[NAV_GRID_MIN_X] = _:fMinX;
    g_nGrid[NAV_GRID_MIN_Y] = _:fMinY;
    
    g_nGrid[NAV_GRID_SIZE_X] = floatround((fMaxX - fMinX) / GRID_CELL_SIZE) + 1;
    g_nGrid[NAV_GRID_SIZE_Y] = floatround((fMaxY - fMinY) / GRID_CELL_SIZE) + 1;
    g_nGrid[NAV_GRID_AREA_COUNT] = 0;
    
    // Initialize hash table
    for(new i = 0; i < 256; i++)
        g_nGrid[NAV_GRID_HASH_TABLE][i] = Invalid_Area;
}

AddAreaToGrid(iAreaIndex)
{
    // Don't use IsValidAreaIndex here because it can be called during loading
    // when g_bNavLoaded is still false
    if(g_aNavAreas == Invalid_Array || iAreaIndex < 0 || iAreaIndex >= ArraySize(g_aNavAreas))
        return;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    // Verify area is not deleted
    if(sArea[NAV_AREA_ID] == 0)
        return;
    
    // Add to hash table by ID
    new iHash = ComputeHashKey(sArea[NAV_AREA_ID]);
    sArea[NAV_AREA_NEXT_HASH] = g_nGrid[NAV_GRID_HASH_TABLE][iHash];
    sArea[NAV_AREA_PREV_HASH] = Invalid_Area;
    
    if(g_nGrid[NAV_GRID_HASH_TABLE][iHash] != Invalid_Area)
    {
        new sOther[NavArea];
        ArrayGetArray(g_aNavAreas, g_nGrid[NAV_GRID_HASH_TABLE][iHash], sOther);
        sOther[NAV_AREA_PREV_HASH] = iAreaIndex;
        ArraySetArray(g_aNavAreas, g_nGrid[NAV_GRID_HASH_TABLE][iHash], sOther);
    }
    
    g_nGrid[NAV_GRID_HASH_TABLE][iHash] = iAreaIndex;
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    
    g_nGrid[NAV_GRID_AREA_COUNT]++;
}

RemoveAreaFromGrid(iAreaIndex)
{
    if(!IsValidAreaIndex(iAreaIndex))
        return;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    // Remove from hash table
    new iHash = ComputeHashKey(sArea[NAV_AREA_ID]);
    
    // Update links
    if(sArea[NAV_AREA_PREV_HASH] != Invalid_Area)
    {
        new sPrev[NavArea];
        ArrayGetArray(g_aNavAreas, sArea[NAV_AREA_PREV_HASH], sPrev);
        sPrev[NAV_AREA_NEXT_HASH] = sArea[NAV_AREA_NEXT_HASH];
        ArraySetArray(g_aNavAreas, sArea[NAV_AREA_PREV_HASH], sPrev);
    }
    else
    {
        // Was first in bucket
        g_nGrid[NAV_GRID_HASH_TABLE][iHash] = sArea[NAV_AREA_NEXT_HASH];
    }
    
    if(sArea[NAV_AREA_NEXT_HASH] != Invalid_Area)
    {
        new sNext[NavArea];
        ArrayGetArray(g_aNavAreas, sArea[NAV_AREA_NEXT_HASH], sNext);
        sNext[NAV_AREA_PREV_HASH] = sArea[NAV_AREA_PREV_HASH];
        ArraySetArray(g_aNavAreas, sArea[NAV_AREA_NEXT_HASH], sNext);
    }
    
    sArea[NAV_AREA_PREV_HASH] = Invalid_Area;
    sArea[NAV_AREA_NEXT_HASH] = Invalid_Area;
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    
    g_nGrid[NAV_GRID_AREA_COUNT]--;
}

ComputeHashKey(iAreaID)
{
    return iAreaID & 0xFF;
}

// Fast search by ID using hash table
FindAreaByIDFast(iAreaID)
{
    if(!g_bNavLoaded || iAreaID == 0)
        return Invalid_Area;
    
    new iHash = ComputeHashKey(iAreaID);
    new iAreaIndex = g_nGrid[NAV_GRID_HASH_TABLE][iHash];
    
    while(iAreaIndex != Invalid_Area)
    {
        new sArea[NavArea];
        ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
        
        if(sArea[NAV_AREA_ID] == iAreaID)
            return iAreaIndex;
        
        iAreaIndex = sArea[NAV_AREA_NEXT_HASH];
    }
    
    return Invalid_Area;
}

// ============================================================================
// Internal Functions - Search
// ============================================================================

Navmesh_GetNearestAreaInternal(const Float:vOrigin[3], Float:fMaxDist, Float:fBeneathLimit)
{
    if(!g_bNavLoaded)
        return Invalid_Area;
    
    new iNearestArea = Invalid_Area;
    new Float:fNearestDist = fMaxDist > 0.0 ? (fMaxDist * fMaxDist) : 999999.9;
    
    new sArea[NavArea];
    for(new i = 0; i < g_iNavAreaCount; i++)
    {
        ArrayGetArray(g_aNavAreas, i, sArea);
        
        // Skip deleted areas
        if(sArea[NAV_AREA_ID] == 0)
            continue;
        
        new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
        new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
        new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
        new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
        
        // Check if point is inside area (2D)
        if(vOrigin[0] >= fLoX && vOrigin[0] <= fHiX &&
           vOrigin[1] >= fLoY && vOrigin[1] <= fHiY)
        {
            // Check height
            new Float:fAreaZ = Navmesh_GetAreaZInternal(i, vOrigin[0], vOrigin[1]);
            new Float:fDZ = vOrigin[2] - fAreaZ;
            
            // If above area and within height limit
            if(fDZ >= -STEP_HEIGHT && fDZ <= fBeneathLimit)
            {
                // Found an area containing the point
                return i;
            }
        }
        
        // If not inside, calculate distance to nearest area
        new Float:fDZ = vOrigin[2] - sArea[NAV_AREA_CENTER_Z];
        if(fDZ > fBeneathLimit || fDZ < -STEP_HEIGHT)
            continue;
        
        // Calculate distance to closest point in area
        new Float:fCloseX = floatclamp(vOrigin[0], fLoX, fHiX);
        new Float:fCloseY = floatclamp(vOrigin[1], fLoY, fHiY);
        
        new Float:fDX = vOrigin[0] - fCloseX;
        new Float:fDY = vOrigin[1] - fCloseY;
        new Float:fDistSq = fDX * fDX + fDY * fDY;
        
        if(fDistSq < fNearestDist)
        {
            fNearestDist = fDistSq;
            iNearestArea = i;
        }
    }
    
    return iNearestArea;
}

bool:Navmesh_IsPointInAreaInternal(iAreaIndex, const Float:vPoint[3])
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    // Check X and Y
    if(vPoint[0] < Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] || 
       vPoint[0] > Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X])
        return false;
    
    if(vPoint[1] < Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] || 
       vPoint[1] > Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y])
        return false;
    
    // Calculate Z at that position
    new Float:fZ = Navmesh_GetAreaZInternal(iAreaIndex, vPoint[0], vPoint[1]);
    
    // Check if close to area floor
    return floatabs(vPoint[2] - fZ) < HALF_HUMAN_HEIGHT;
}

Float:Navmesh_GetAreaZInternal(iAreaIndex, Float:fX, Float:fY)
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    // Bilinear interpolation of the 4 corners
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    new Float:fDX = (fHiX - fLoX);
    new Float:fDY = (fHiY - fLoY);
    
    if(fDX == 0.0 || fDY == 0.0)
        return sArea[NAV_AREA_CENTER_Z];
    
    new Float:fU = (fX - fLoX) / fDX;
    new Float:fV = (fY - fLoY) / fDY;
    
    fU = floatclamp(fU, 0.0, 1.0);
    fV = floatclamp(fV, 0.0, 1.0);
    
    // Heights of the 4 corners
    new Float:fNWZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z];
    new Float:fNEZ = sArea[NAV_AREA_NE_Z];
    new Float:fSEZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z];
    new Float:fSWZ = sArea[NAV_AREA_SW_Z];
    
    // Interpolation
    new Float:fNorthZ = fNWZ + fU * (fNEZ - fNWZ);
    new Float:fSouthZ = fSWZ + fU * (fSEZ - fSWZ);
    
    return fNorthZ + fV * (fSouthZ - fNorthZ);
}

// ============================================================================
// Utilities
// ============================================================================

bool:IsValidAreaIndex(iAreaIndex)
{
    if(!g_bNavLoaded || g_aNavAreas == Invalid_Array)
        return false;
    
    if(iAreaIndex < 0 || iAreaIndex >= ArraySize(g_aNavAreas))
        return false;
    
    // Verify area is not deleted
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return (sArea[NAV_AREA_ID] != 0);
}

FindAreaByID(iAreaID)
{
    // Use fast hash search if grid is initialized
    return FindAreaByIDFast(iAreaID);
}

Array:GetAreaConnectArray(const sArea[NavArea], NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: return sArea[NAV_AREA_CONNECT_NORTH];
        case NAV_DIR_EAST:  return sArea[NAV_AREA_CONNECT_EAST];
        case NAV_DIR_SOUTH: return sArea[NAV_AREA_CONNECT_SOUTH];
        case NAV_DIR_WEST:  return sArea[NAV_AREA_CONNECT_WEST];
    }
    return Invalid_Array;
}

// File reading functions moved to navmesh_file.inc
// ============================================================================
// Pathfinding A*
// ============================================================================

bool:BuildPathAStar(iStartArea, iGoalArea, Array:aPathOut, const Float:vStartActual[3], const Float:vGoalActual[3])
{
    if(iStartArea == iGoalArea)
    {
        // Trivial path - start and goal in same area (mirrors CNavPath::BuildTrivialPath)
        BuildTrivialPath(iStartArea, iGoalArea, aPathOut, vStartActual, vGoalActual);
        return true;
    }
    
    // Increment global marker
    static iMasterMarker = 1;
    iMasterMarker++;
    
    // Initialize start area
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iStartArea, sArea);
    sArea[NAV_AREA_COST_SO_FAR] = 0.0;
    sArea[NAV_AREA_TOTAL_COST] = GetHeuristicCost(iStartArea, iGoalArea);
    sArea[NAV_AREA_PARENT] = Invalid_Area;
    sArea[NAV_AREA_MARKER] = iMasterMarker;
    sArea[NAV_AREA_OPEN_MARKER] = iMasterMarker;
    ArraySetArray(g_aNavAreas, iStartArea, sArea);
    
    // Simple open list (index array)
    new Array:aOpenList = ArrayCreate();
    ArrayPushCell(aOpenList, iStartArea);
    
    new bool:bPathFound = false;
    // Track closest area to goal in case full path fails (mirrors NavAreaBuildPath)
    new iClosestArea = iStartArea;
    new Float:fClosestDist = GetHeuristicCost(iStartArea, iGoalArea);
    new iIterations = 0;
    new const MAX_ITERATIONS = 1000;
    
    while(ArraySize(aOpenList) > 0 && iIterations < MAX_ITERATIONS)
    {
        iIterations++;
        
        // Find area with lowest total cost in open list
        new iCurrentArea = PopLowestCostArea(aOpenList);
        
        if(iCurrentArea == Invalid_Area)
            break;
        
        // Did we reach the goal?
        if(iCurrentArea == iGoalArea)
        {
            bPathFound = true;
            break;
        }
        
        // Explore neighbors
        ArrayGetArray(g_aNavAreas, iCurrentArea, sArea);
        
        for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
        {
            new Array:aConnect = GetAreaConnectArray(sArea, dir);
            if(aConnect == Invalid_Array)
                continue;
            
            for(new i = 0; i < ArraySize(aConnect); i++)
            {
                new sConnect[NavConnect];
                ArrayGetArray(aConnect, i, sConnect);
                
                new iNeighborArea = sConnect[NAV_CONNECT_AREA];
                if(iNeighborArea == Invalid_Area)
                    continue;
                
                // Don't backtrack to the area we came from (mirrors KitRifty's NavMeshBuildPath)
                if(iNeighborArea == sArea[NAV_AREA_PARENT])
                    continue;
                
                new sNeighbor[NavArea];
                ArrayGetArray(g_aNavAreas, iNeighborArea, sNeighbor);
                
                // Calculate new cost
                new Float:fNewCost = sArea[NAV_AREA_COST_SO_FAR] + GetMoveCost(iCurrentArea, iNeighborArea);
                
                // If not visited or we found a better path
                if(sNeighbor[NAV_AREA_MARKER] != iMasterMarker || fNewCost < sNeighbor[NAV_AREA_COST_SO_FAR])
                {
                    new Float:fHeur = GetHeuristicCost(iNeighborArea, iGoalArea);
                    
                    sNeighbor[NAV_AREA_COST_SO_FAR] = fNewCost;
                    sNeighbor[NAV_AREA_TOTAL_COST] = fNewCost + fHeur;
                    sNeighbor[NAV_AREA_PARENT] = iCurrentArea;
                    sNeighbor[NAV_AREA_PARENT_HOW] = NavTraverseType:dir;
                    sNeighbor[NAV_AREA_MARKER] = iMasterMarker;
                    
                    // Track closest area in case the full path fails
                    if(fHeur < fClosestDist)
                    {
                        fClosestDist = fHeur;
                        iClosestArea = iNeighborArea;
                    }
                    
                    // Add to open list if not there
                    if(sNeighbor[NAV_AREA_OPEN_MARKER] != iMasterMarker)
                    {
                        sNeighbor[NAV_AREA_OPEN_MARKER] = iMasterMarker;
                        ArrayPushCell(aOpenList, iNeighborArea);
                    }
                    
                    ArraySetArray(g_aNavAreas, iNeighborArea, sNeighbor);
                }
            }
        }
    }
    
    ArrayDestroy(aOpenList);
    
    // If no full path, fall back to closest reachable area (mirrors NavAreaBuildPath closestArea)
    new iEffectiveGoal = bPathFound ? iGoalArea : iClosestArea;
    
    if(iEffectiveGoal == iStartArea)
    {
        BuildTrivialPath(iStartArea, iStartArea, aPathOut, vStartActual, vGoalActual);
        return bPathFound;
    }
    
    // Reconstruct path from goal to start (goal-first order)
    new iCurrentArea = iEffectiveGoal;
    new Array:aTempPath = ArrayCreate();
    
    while(iCurrentArea != Invalid_Area && iCurrentArea != iStartArea)
    {
        ArrayPushCell(aTempPath, iCurrentArea);
        
        ArrayGetArray(g_aNavAreas, iCurrentArea, sArea);
        iCurrentArea = sArea[NAV_AREA_PARENT];
    }
    
    ArrayPushCell(aTempPath, iStartArea);
    
    // Compute actual path positions: portal smoothing + jump-down insertion + ladder fallback
    // (mirrors CNavPath::ComputePathPositions)
    ComputePathPositions(aTempPath, aPathOut, vStartActual, vGoalActual);
    
    ArrayDestroy(aTempPath);
    
    return bPathFound;
}

PopLowestCostArea(Array:aOpenList)
{
    if(ArraySize(aOpenList) == 0)
        return Invalid_Area;
    
    new iLowestIndex = 0;
    new Float:fLowestCost = 999999.9;
    new sArea[NavArea];
    
    for(new i = 0; i < ArraySize(aOpenList); i++)
    {
        new iArea = ArrayGetCell(aOpenList, i);
        ArrayGetArray(g_aNavAreas, iArea, sArea);
        
        if(sArea[NAV_AREA_TOTAL_COST] < fLowestCost)
        {
            fLowestCost = sArea[NAV_AREA_TOTAL_COST];
            iLowestIndex = i;
        }
    }
    
    new iResult = ArrayGetCell(aOpenList, iLowestIndex);
    ArrayDeleteItem(aOpenList, iLowestIndex);
    
    return iResult;
}

Float:GetHeuristicCost(iFromArea, iToArea)
{
    new sFrom[NavArea], sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    // 2D Euclidean distance
    new Float:fDX = sTo[NAV_AREA_CENTER_X] - sFrom[NAV_AREA_CENTER_X];
    new Float:fDY = sTo[NAV_AREA_CENTER_Y] - sFrom[NAV_AREA_CENTER_Y];
    
    return floatsqroot(fDX * fDX + fDY * fDY);
}

Float:GetMoveCost(iFromArea, iToArea)
{
    // Base cost is distance
    new Float:fDist = GetHeuristicCost(iFromArea, iToArea);
    new Float:fCost = fDist;
    
    // Add penalties for attributes (mirrors ReGameDLL ShortestPathCost)
    new sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    if(sTo[NAV_AREA_ATTRIBUTES] & NAV_ATTR_CROUCH)
        fCost += 20.0 * fDist; // crouchPenalty
    
    if(sTo[NAV_AREA_ATTRIBUTES] & NAV_ATTR_JUMP)
        fCost += 5.0 * fDist;  // jumpPenalty
    
    return fCost;
}

NavDirType:GetDirectionFromTo(iFromArea, iToArea)
{
    new sFrom[NavArea], sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    new Float:fDX = sTo[NAV_AREA_CENTER_X] - sFrom[NAV_AREA_CENTER_X];
    new Float:fDY = sTo[NAV_AREA_CENTER_Y] - sFrom[NAV_AREA_CENTER_Y];
    
    // Determine predominant direction
    if(floatabs(fDX) > floatabs(fDY))
    {
        return (fDX > 0.0) ? NAV_DIR_EAST : NAV_DIR_WEST;
    }
    else
    {
        return (fDY > 0.0) ? NAV_DIR_SOUTH : NAV_DIR_NORTH;
    }
}

// Builds a trivial 2-segment path when start and goal are in the same area
// (mirrors CNavPath::BuildTrivialPath from ReGameDLL_CS).
// vStartActual / vGoalActual are the bot's origin and exact goal position;
// the segments use them with Z snapped to the area floor so the bot doesn't
// have to detour through area centers.
BuildTrivialPath(iStartArea, iGoalArea, Array:aPathOut, const Float:vStartActual[3], const Float:vGoalActual[3])
{
    new sSeg[NavPathSegment];
    sSeg[NAV_PATH_AREA] = iStartArea;
    sSeg[NAV_PATH_HOW] = NUM_NAV_TRAVERSE_TYPES;
    sSeg[NAV_PATH_POS_X] = vStartActual[0];
    sSeg[NAV_PATH_POS_Y] = vStartActual[1];
    sSeg[NAV_PATH_POS_Z] = Navmesh_GetAreaZInternal(iStartArea, vStartActual[0], vStartActual[1]);
    ArrayPushArray(aPathOut, sSeg);
    
    if(iStartArea != iGoalArea)
    {
        sSeg[NAV_PATH_AREA] = iGoalArea;
        sSeg[NAV_PATH_HOW] = NUM_NAV_TRAVERSE_TYPES;
        sSeg[NAV_PATH_POS_X] = vGoalActual[0];
        sSeg[NAV_PATH_POS_Y] = vGoalActual[1];
        sSeg[NAV_PATH_POS_Z] = Navmesh_GetAreaZInternal(iGoalArea, vGoalActual[0], vGoalActual[1]);
        ArrayPushArray(aPathOut, sSeg);
    }
}

// Returns true if iAreaB has any connection back to iAreaA in any direction.
// Used to detect "jump down" links (one-way connections) during path building.
bool:IsBidirectionallyConnected(iAreaA, iAreaB)
{
    new sB[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaB, sB);
    
    for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
    {
        new Array:aConnect = GetAreaConnectArray(sB, dir);
        if(aConnect == Invalid_Array)
            continue;
        
        for(new i = 0; i < ArraySize(aConnect); i++)
        {
            new sConnect[NavConnect];
            ArrayGetArray(aConnect, i, sConnect);
            if(sConnect[NAV_CONNECT_AREA] == iAreaA)
                return true;
        }
    }
    return false;
}

// Walks the parent chain (goal-first in aTempPath) and produces forward-ordered
// segments in aPathOut. Smooths positions through portals, inserts an extra
// node at the bottom of "jump down" links, and falls back to centers for ladder
// traversals (mirrors CNavPath::ComputePathPositions from ReGameDLL_CS).
ComputePathPositions(Array:aTempPath, Array:aPathOut, const Float:vStartActual[3], const Float:vGoalActual[3])
{
    new iCount = ArraySize(aTempPath);
    if(iCount == 0)
        return;
    
    // Start segment: bot's actual origin (XY) snapped to start area floor (Z).
    // Mirrors CCSBot::ComputePath: m_path[0].pos = pev->origin.
    new iStartArea = ArrayGetCell(aTempPath, iCount - 1);
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iStartArea, sArea);
    
    new sSeg[NavPathSegment];
    sSeg[NAV_PATH_AREA] = iStartArea;
    sSeg[NAV_PATH_HOW] = NUM_NAV_TRAVERSE_TYPES;
    sSeg[NAV_PATH_POS_X] = vStartActual[0];
    sSeg[NAV_PATH_POS_Y] = vStartActual[1];
    sSeg[NAV_PATH_POS_Z] = Navmesh_GetAreaZInternal(iStartArea, vStartActual[0], vStartActual[1]);
    ArrayPushArray(aPathOut, sSeg);
    
    new iPrevArea = iStartArea;
    new Float:vFromPos[3];
    vFromPos[0] = sSeg[NAV_PATH_POS_X];
    vFromPos[1] = sSeg[NAV_PATH_POS_Y];
    vFromPos[2] = sSeg[NAV_PATH_POS_Z];
    
    // iCount-2 down to 0 walks start->goal
    for(new i = iCount - 2; i >= 0; i--)
    {
        new iToArea = ArrayGetCell(aTempPath, i);
        ArrayGetArray(g_aNavAreas, iToArea, sArea);
        new NavTraverseType:how = sArea[NAV_AREA_PARENT_HOW];
        
        new sFromArea[NavArea];
        ArrayGetArray(g_aNavAreas, iPrevArea, sFromArea);
        
        new Float:vToPos[3];
        new bool:bIsFloor = (_:how <= _:NAV_TRAVERSE_WEST);
        
        if(bIsFloor)
        {
            // Closest point on shared edge keeps path straight
            ComputeClosestPointInPortal(sFromArea, sArea, NavDirType:how, vFromPos, vToPos);
            
            // Step into the destination area a bit (must be < min area size)
            Navmesh_AddDirectionVector(vToPos, NavDirType:how, 5.0);
            
            // Use Z of the from-area so we can walk out
            vToPos[2] = Navmesh_GetAreaZInternal(iPrevArea, vToPos[0], vToPos[1]);
            
            // Detect "jump down" link: one-way connection from-area -> to-area
            if(!IsBidirectionallyConnected(iPrevArea, iToArea))
            {
                // Push top of jump-down out so we get over the ledge
                new Float:fPushDist = 25.0;
                new Float:vDir2D[2];
                Navmesh_DirectionToVector(NavDirType:how, vDir2D);
                vToPos[0] += fPushDist * vDir2D[0];
                vToPos[1] += fPushDist * vDir2D[1];
                
                // Top-of-fall segment
                sSeg[NAV_PATH_AREA] = iToArea;
                sSeg[NAV_PATH_HOW] = how;
                sSeg[NAV_PATH_POS_X] = vToPos[0];
                sSeg[NAV_PATH_POS_Y] = vToPos[1];
                sSeg[NAV_PATH_POS_Z] = vToPos[2];
                ArrayPushArray(aPathOut, sSeg);
                
                // Bottom-of-fall extra segment, on the destination area floor
                new Float:vBot[3];
                vBot[0] = vToPos[0] + fPushDist * vDir2D[0];
                vBot[1] = vToPos[1] + fPushDist * vDir2D[1];
                vBot[2] = Navmesh_GetAreaZInternal(iToArea, vBot[0], vBot[1]);
                
                sSeg[NAV_PATH_AREA] = iToArea;
                sSeg[NAV_PATH_HOW] = how;
                sSeg[NAV_PATH_POS_X] = vBot[0];
                sSeg[NAV_PATH_POS_Y] = vBot[1];
                sSeg[NAV_PATH_POS_Z] = vBot[2];
                ArrayPushArray(aPathOut, sSeg);
                
                vFromPos[0] = vBot[0];
                vFromPos[1] = vBot[1];
                vFromPos[2] = vBot[2];
                iPrevArea = iToArea;
                continue;
            }
        }
        else
        {
            // Ladder traversal not fully modeled; fall back to destination center
            vToPos[0] = sArea[NAV_AREA_CENTER_X];
            vToPos[1] = sArea[NAV_AREA_CENTER_Y];
            vToPos[2] = sArea[NAV_AREA_CENTER_Z];
        }
        
        sSeg[NAV_PATH_AREA] = iToArea;
        sSeg[NAV_PATH_HOW] = how;
        sSeg[NAV_PATH_POS_X] = vToPos[0];
        sSeg[NAV_PATH_POS_Y] = vToPos[1];
        sSeg[NAV_PATH_POS_Z] = vToPos[2];
        ArrayPushArray(aPathOut, sSeg);
        
        vFromPos[0] = vToPos[0];
        vFromPos[1] = vToPos[1];
        vFromPos[2] = vToPos[2];
        iPrevArea = iToArea;
    }
    
    // Append the actual goal position as the final segment (mirrors
    // CCSBot::ComputePath: m_path[m_pathLength].pos = pathEndPosition).
    // Without this the path ends at the entry portal of the goal area; with
    // it the bot walks all the way to the real victim/target spot.
    new iGoalArea = ArrayGetCell(aTempPath, 0);
    sSeg[NAV_PATH_AREA] = iGoalArea;
    sSeg[NAV_PATH_HOW] = NUM_NAV_TRAVERSE_TYPES;
    sSeg[NAV_PATH_POS_X] = vGoalActual[0];
    sSeg[NAV_PATH_POS_Y] = vGoalActual[1];
    sSeg[NAV_PATH_POS_Z] = Navmesh_GetAreaZInternal(iGoalArea, vGoalActual[0], vGoalActual[1]);
    ArrayPushArray(aPathOut, sSeg);
}

// ============================================================================
// Geometry Helper Functions
// ============================================================================

GetClosestPointInArea(iAreaIndex, const Float:vPos[3], Float:vClose[3])
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    // Clamp X and Y to area bounds
    vClose[0] = floatclamp(vPos[0], fLoX, fHiX);
    vClose[1] = floatclamp(vPos[1], fLoY, fHiY);
    vClose[2] = Navmesh_GetAreaZInternal(iAreaIndex, vClose[0], vClose[1]);
}

Float:GetDistanceSquaredToArea(iAreaIndex, const Float:vPos[3])
{
    new Float:vClose[3];
    GetClosestPointInArea(iAreaIndex, vPos, vClose);
    
    new Float:fDX = vPos[0] - vClose[0];
    new Float:fDY = vPos[1] - vClose[1];
    new Float:fDZ = vPos[2] - vClose[2];
    
    return fDX * fDX + fDY * fDY + fDZ * fDZ;
}

GetRandomPositionInArea(iAreaIndex, Float:vPos[3])
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    // Random position inside area
    vPos[0] = random_float(fLoX, fHiX);
    vPos[1] = random_float(fLoY, fHiY);
    vPos[2] = Navmesh_GetAreaZInternal(iAreaIndex, vPos[0], vPos[1]);
}

// ============================================================================
// Helper Functions - Corners and Portals
// ============================================================================

GetAreaCorner(const sArea[NavArea], NavCornerType:corner, Float:vPos[3])
{
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fLoZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    switch(corner)
    {
        case NAV_CORNER_NORTH_WEST:
        {
            vPos[0] = fLoX;
            vPos[1] = fLoY;
            vPos[2] = fLoZ;
        }
        case NAV_CORNER_NORTH_EAST:
        {
            vPos[0] = fHiX;
            vPos[1] = fLoY;
            vPos[2] = sArea[NAV_AREA_NE_Z];
        }
        case NAV_CORNER_SOUTH_EAST:
        {
            vPos[0] = fHiX;
            vPos[1] = fHiY;
            vPos[2] = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z];
        }
        case NAV_CORNER_SOUTH_WEST:
        {
            vPos[0] = fLoX;
            vPos[1] = fHiY;
            vPos[2] = sArea[NAV_AREA_SW_Z];
        }
    }
}

bool:IsOverlappingPoint(const sArea[NavArea], const Float:vPos[3])
{
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    return (vPos[0] >= fLoX && vPos[0] <= fHiX && 
            vPos[1] >= fLoY && vPos[1] <= fHiY);
}

bool:AreAreasOverlapping(const sArea1[NavArea], const sArea2[NavArea])
{
    new Float:fLo1X = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLo1Y = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHi1X = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHi1Y = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    new Float:fLo2X = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLo2Y = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHi2X = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHi2Y = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    // Check if rectangles overlap
    if(fLo1X > fHi2X || fLo2X > fHi1X)
        return false;
    
    if(fLo1Y > fHi2Y || fLo2Y > fHi1Y)
        return false;
    
    return true;
}

ComputePortal(const sFrom[NavArea], const sTo[NavArea], NavDirType:dir, Float:vCenter[3], &Float:fHalfWidth)
{
    new Float:fFromLoX = Float:sFrom[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fFromLoY = Float:sFrom[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fFromHiX = Float:sFrom[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fFromHiY = Float:sFrom[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    new Float:fToLoX = Float:sTo[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fToLoY = Float:sTo[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fToHiX = Float:sTo[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fToHiY = Float:sTo[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    switch(dir)
    {
        case NAV_DIR_NORTH, NAV_DIR_SOUTH:
        {
            // Horizontal portal
            new Float:fLeft = floatmax(fFromLoX, fToLoX);
            new Float:fRight = floatmin(fFromHiX, fToHiX);
            
            vCenter[0] = (fLeft + fRight) / 2.0;
            vCenter[1] = (dir == NAV_DIR_NORTH) ? fFromLoY : fFromHiY;
            fHalfWidth = (fRight - fLeft) / 2.0;
        }
        case NAV_DIR_EAST, NAV_DIR_WEST:
        {
            // Vertical portal
            new Float:fTop = floatmax(fFromLoY, fToLoY);
            new Float:fBottom = floatmin(fFromHiY, fToHiY);
            
            vCenter[0] = (dir == NAV_DIR_EAST) ? fFromHiX : fFromLoX;
            vCenter[1] = (fTop + fBottom) / 2.0;
            fHalfWidth = (fBottom - fTop) / 2.0;
        }
    }
    
    // Calculate Z at portal center
    vCenter[2] = (sFrom[NAV_AREA_CENTER_Z] + sTo[NAV_AREA_CENTER_Z]) / 2.0;
}

ComputeClosestPointInPortal(const sFrom[NavArea], const sTo[NavArea], NavDirType:dir, const Float:vFromPos[3], Float:vClosePos[3])
{
    new Float:vPortalCenter[3], Float:fHalfWidth;
    ComputePortal(sFrom, sTo, dir, vPortalCenter, fHalfWidth);
    
    switch(dir)
    {
        case NAV_DIR_NORTH, NAV_DIR_SOUTH:
        {
            // Clamp X to portal
            vClosePos[0] = floatclamp(vFromPos[0], vPortalCenter[0] - fHalfWidth, vPortalCenter[0] + fHalfWidth);
            vClosePos[1] = vPortalCenter[1];
        }
        case NAV_DIR_EAST, NAV_DIR_WEST:
        {
            // Clamp Y to portal
            vClosePos[0] = vPortalCenter[0];
            vClosePos[1] = floatclamp(vFromPos[1], vPortalCenter[1] - fHalfWidth, vPortalCenter[1] + fHalfWidth);
        }
    }
    
    vClosePos[2] = vPortalCenter[2];
}

// ============================================================================
// Natives - Editing
// ============================================================================

public native_create_area(plugin_id, num_params)
{
    new Float:vMins[3], Float:vMaxs[3];
    get_array_f(1, vMins, 3);
    get_array_f(2, vMaxs, 3);
    
    return CreateAreaInternal(vMins, vMaxs);
}

public bool:native_delete_area(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    return DeleteAreaInternal(iAreaIndex);
}

public bool:native_set_area_attributes(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new NavAttributeType:attrs = NavAttributeType:get_param(2);
    
    if(!IsValidAreaIndex(iAreaIndex))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    sArea[NAV_AREA_ATTRIBUTES] = attrs;
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    
    return true;
}

public bool:native_connect_areas(plugin_id, num_params)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidAreaIndex(iFromArea) || !IsValidAreaIndex(iToArea))
        return false;
    
    return ConnectAreasInternal(iFromArea, iToArea, dir);
}

public bool:native_disconnect_areas(plugin_id, num_params)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidAreaIndex(iFromArea) || !IsValidAreaIndex(iToArea))
        return false;
    
    return DisconnectAreasInternal(iFromArea, iToArea, dir);
}

public bool:native_set_corner_z(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new NavCornerType:corner = NavCornerType:get_param(2);
    new Float:fZ = get_param_f(3);
    
    if(!IsValidAreaIndex(iAreaIndex) || corner >= NUM_NAV_CORNERS)
        return false;
    
    return SetCornerZInternal(iAreaIndex, corner, fZ);
}

public bool:native_set_area_extent(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new NavDirType:dir = NavDirType:get_param(2);
    new Float:fAmount = get_param_f(3);
    
    if(!IsValidAreaIndex(iAreaIndex) || dir >= NUM_NAV_DIRECTIONS)
        return false;
    
    return SetAreaExtentInternal(iAreaIndex, dir, fAmount);
}

public bool:native_save(plugin_id, num_params)
{
    new szMapName[32];
    get_string(1, szMapName, charsmax(szMapName));
    
    return SaveNavmeshInternal(szMapName);
}

// ============================================================================
// Internal Functions - Editing
// ============================================================================

// Gets Z height at point (x,y) in area using bilinear interpolation
// Based on CNavArea::GetZ from ReGameDLL_CS
Float:GetAreaZInternal(const sArea[NavArea], Float:fX, Float:fY)
{
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    // Heights of the 4 corners
    new Float:fNwZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z]; // NW = lo
    new Float:fNeZ = Float:sArea[NAV_AREA_NE_Z];
    new Float:fSwZ = Float:sArea[NAV_AREA_SW_Z];
    new Float:fSeZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z]; // SE = hi
    
    // Calculate interpolation factors
    new Float:fDX = fHiX - fLoX;
    new Float:fDY = fHiY - fLoY;
    
    if(fDX == 0.0 || fDY == 0.0)
        return Float:sArea[NAV_AREA_CENTER_Z];
    
    new Float:fU = (fX - fLoX) / fDX;
    new Float:fV = (fY - fLoY) / fDY;
    
    // Clamp to [0,1]
    fU = floatclamp(fU, 0.0, 1.0);
    fV = floatclamp(fV, 0.0, 1.0);
    
    // Bilinear interpolation
    new Float:fNorthZ = fNwZ + fU * (fNeZ - fNwZ);
    new Float:fSouthZ = fSwZ + fU * (fSeZ - fSwZ);
    
    return fNorthZ + fV * (fSouthZ - fNorthZ);
}

// Creates an area with 4 corners (allows sloped areas)
CreateAreaWithCornersInternal(const Float:vNW[3], const Float:vNE[3], const Float:vSE[3], const Float:vSW[3])
{
    if(g_aNavAreas == Invalid_Array)
        return Invalid_Area;
    
    new sArea[NavArea];
    
    sArea[NAV_AREA_ID] = g_iNextAreaID++;
    sArea[NAV_AREA_PLACE] = UNDEFINED_PLACE;
    
    // NW is lo, SE is hi
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] = _:vNW[0];
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] = _:vNW[1];
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z] = _:vNW[2];
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X] = _:vSE[0];
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y] = _:vSE[1];
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z] = _:vSE[2];
    
    // NE and SW corner heights
    sArea[NAV_AREA_NE_Z] = _:vNE[2];
    sArea[NAV_AREA_SW_Z] = _:vSW[2];
    
    // Center
    sArea[NAV_AREA_CENTER_X] = (vNW[0] + vSE[0]) / 2.0;
    sArea[NAV_AREA_CENTER_Y] = (vNW[1] + vSE[1]) / 2.0;
    sArea[NAV_AREA_CENTER_Z] = (vNW[2] + vSE[2]) / 2.0;
    
    sArea[NAV_AREA_ATTRIBUTES] = NavAttributeType:0;
    
    sArea[NAV_AREA_CONNECT_NORTH] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_EAST] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_SOUTH] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_WEST] = ArrayCreate(NavConnect);
    
    sArea[NAV_AREA_APPROACH] = ArrayCreate(NavApproachInfo);
    sArea[NAV_AREA_APPROACH_COUNT] = 0;
    
    sArea[NAV_AREA_TOTAL_COST] = _:0.0;
    sArea[NAV_AREA_COST_SO_FAR] = _:0.0;
    sArea[NAV_AREA_PARENT] = Invalid_Area;
    sArea[NAV_AREA_PARENT_HOW] = NAV_TRAVERSE_NORTH;
    sArea[NAV_AREA_MARKER] = 0;
    sArea[NAV_AREA_OPEN_MARKER] = 0;
    sArea[NAV_AREA_PREV_HASH] = Invalid_Area;
    sArea[NAV_AREA_NEXT_HASH] = Invalid_Area;
    
    new iNewIndex = ArraySize(g_aNavAreas);
    ArrayPushArray(g_aNavAreas, sArea);
    g_iNavAreaCount++;
    
    AddAreaToGrid(iNewIndex);
    
    return iNewIndex;
}

CreateAreaInternal(const Float:vMins[3], const Float:vMaxs[3])
{
    if(g_aNavAreas == Invalid_Array)
        return Invalid_Area;
    
    // Create new area
    new sArea[NavArea];
    
    // Assign unique ID
    sArea[NAV_AREA_ID] = g_iNextAreaID++;
    sArea[NAV_AREA_PLACE] = UNDEFINED_PLACE;
    
    // Sort coordinates (ensure mins < maxs)
    new Float:fLoX = floatmin(vMins[0], vMaxs[0]);
    new Float:fLoY = floatmin(vMins[1], vMaxs[1]);
    new Float:fLoZ = floatmin(vMins[2], vMaxs[2]);
    new Float:fHiX = floatmax(vMins[0], vMaxs[0]);
    new Float:fHiY = floatmax(vMins[1], vMaxs[1]);
    new Float:fHiZ = floatmax(vMins[2], vMaxs[2]);
    
    // Set extent
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] = _:fLoX;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] = _:fLoY;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z] = _:fLoZ;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X] = _:fHiX;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y] = _:fHiY;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z] = _:fHiZ;
    
    // Calculate center
    sArea[NAV_AREA_CENTER_X] = (fLoX + fHiX) / 2.0;
    sArea[NAV_AREA_CENTER_Y] = (fLoY + fHiY) / 2.0;
    sArea[NAV_AREA_CENTER_Z] = (fLoZ + fHiZ) / 2.0;
    
    // Corner heights (flat by default)
    sArea[NAV_AREA_NE_Z] = _:fLoZ;
    sArea[NAV_AREA_SW_Z] = _:fLoZ;
    
    // No attributes
    sArea[NAV_AREA_ATTRIBUTES] = NavAttributeType:0;
    
    // Create empty connection arrays
    sArea[NAV_AREA_CONNECT_NORTH] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_EAST] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_SOUTH] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_WEST] = ArrayCreate(NavConnect);
    
    // No approach areas
    sArea[NAV_AREA_APPROACH] = ArrayCreate(NavApproachInfo);
    sArea[NAV_AREA_APPROACH_COUNT] = 0;
    
    // Initialize pathfinding
    sArea[NAV_AREA_TOTAL_COST] = _:0.0;
    sArea[NAV_AREA_COST_SO_FAR] = _:0.0;
    sArea[NAV_AREA_PARENT] = Invalid_Area;
    sArea[NAV_AREA_PARENT_HOW] = NAV_TRAVERSE_NORTH;
    sArea[NAV_AREA_MARKER] = 0;
    sArea[NAV_AREA_OPEN_MARKER] = 0;
    sArea[NAV_AREA_PREV_HASH] = Invalid_Area;
    sArea[NAV_AREA_NEXT_HASH] = Invalid_Area;
    
    // Add to array
    new iNewIndex = ArraySize(g_aNavAreas);
    ArrayPushArray(g_aNavAreas, sArea);
    g_iNavAreaCount++;
    
    // Add to grid
    AddAreaToGrid(iNewIndex);
    
    return iNewIndex;
}

bool:DeleteAreaInternal(iAreaIndex)
{
    // Verify valid index without checking ID (because we're going to delete it)
    if(!g_bNavLoaded || iAreaIndex < 0 || iAreaIndex >= ArraySize(g_aNavAreas))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    // Already deleted
    if(sArea[NAV_AREA_ID] == 0)
        return false;
    
    // Remove from hash grid
    RemoveAreaFromGrid(iAreaIndex);
    
    // Remove connections from other areas to this one
    RemoveAllConnectionsToArea(iAreaIndex);
    
    // Destroy connection arrays
    if(sArea[NAV_AREA_CONNECT_NORTH] != Invalid_Array)
        ArrayDestroy(sArea[NAV_AREA_CONNECT_NORTH]);
    if(sArea[NAV_AREA_CONNECT_EAST] != Invalid_Array)
        ArrayDestroy(sArea[NAV_AREA_CONNECT_EAST]);
    if(sArea[NAV_AREA_CONNECT_SOUTH] != Invalid_Array)
        ArrayDestroy(sArea[NAV_AREA_CONNECT_SOUTH]);
    if(sArea[NAV_AREA_CONNECT_WEST] != Invalid_Array)
        ArrayDestroy(sArea[NAV_AREA_CONNECT_WEST]);
    if(sArea[NAV_AREA_APPROACH] != Invalid_Array)
        ArrayDestroy(sArea[NAV_AREA_APPROACH]);
    
    // Mark as deleted (ID = 0)
    sArea[NAV_AREA_ID] = 0;
    sArea[NAV_AREA_CONNECT_NORTH] = Invalid_Array;
    sArea[NAV_AREA_CONNECT_EAST] = Invalid_Array;
    sArea[NAV_AREA_CONNECT_SOUTH] = Invalid_Array;
    sArea[NAV_AREA_CONNECT_WEST] = Invalid_Array;
    sArea[NAV_AREA_APPROACH] = Invalid_Array;
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    
    return true;
}

RemoveAllConnectionsToArea(iTargetArea)
{
    new iCount = ArraySize(g_aNavAreas);
    
    for(new i = 0; i < iCount; i++)
    {
        if(i == iTargetArea)
            continue;
        
        new sArea[NavArea];
        ArrayGetArray(g_aNavAreas, i, sArea);
        
        if(sArea[NAV_AREA_ID] == 0) // Deleted area
            continue;
        
        // Check each direction
        for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
        {
            new Array:aConnect = GetAreaConnectArray(sArea, dir);
            if(aConnect == Invalid_Array)
                continue;
            
            // Find and remove connection
            for(new j = ArraySize(aConnect) - 1; j >= 0; j--)
            {
                new sConnect[NavConnect];
                ArrayGetArray(aConnect, j, sConnect);
                
                if(sConnect[NAV_CONNECT_AREA] == iTargetArea)
                {
                    ArrayDeleteItem(aConnect, j);
                }
            }
        }
    }
}

bool:ConnectAreasInternal(iFromArea, iToArea, NavDirType:dir)
{
    new sFrom[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    
    new Array:aConnect = GetAreaConnectArray(sFrom, dir);
    if(aConnect == Invalid_Array)
        return false;
    
    // Check if connection already exists
    for(new i = 0; i < ArraySize(aConnect); i++)
    {
        new sConnect[NavConnect];
        ArrayGetArray(aConnect, i, sConnect);
        
        if(sConnect[NAV_CONNECT_AREA] == iToArea)
            return true; // Already connected
    }
    
    // Add new connection
    new sConnect[NavConnect];
    new sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    sConnect[NAV_CONNECT_ID] = sTo[NAV_AREA_ID];
    sConnect[NAV_CONNECT_AREA] = iToArea;
    ArrayPushArray(aConnect, sConnect);
    
    return true;
}

bool:DisconnectAreasInternal(iFromArea, iToArea, NavDirType:dir)
{
    new sFrom[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    
    new Array:aConnect = GetAreaConnectArray(sFrom, dir);
    if(aConnect == Invalid_Array)
        return false;
    
    // Find and remove connection
    for(new i = 0; i < ArraySize(aConnect); i++)
    {
        new sConnect[NavConnect];
        ArrayGetArray(aConnect, i, sConnect);
        
        if(sConnect[NAV_CONNECT_AREA] == iToArea)
        {
            ArrayDeleteItem(aConnect, i);
            return true;
        }
    }
    
    return false;
}

bool:SetCornerZInternal(iAreaIndex, NavCornerType:corner, Float:fZ)
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    switch(corner)
    {
        case NAV_CORNER_NORTH_WEST:
        {
            sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z] = _:fZ;
        }
        case NAV_CORNER_NORTH_EAST:
        {
            sArea[NAV_AREA_NE_Z] = _:fZ;
        }
        case NAV_CORNER_SOUTH_EAST:
        {
            sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z] = _:fZ;
        }
        case NAV_CORNER_SOUTH_WEST:
        {
            sArea[NAV_AREA_SW_Z] = _:fZ;
        }
    }
    
    // Recalculate center Z
    new Float:fLoZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z];
    new Float:fHiZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z];
    sArea[NAV_AREA_CENTER_Z] = (fLoZ + fHiZ) / 2.0;
    
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    return true;
}

bool:SetAreaExtentInternal(iAreaIndex, NavDirType:dir, Float:fAmount)
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    // Ajustar el lado según la dirección
    // NORTH = Y menor (lo_y), SOUTH = Y mayor (hi_y)
    // WEST = X menor (lo_x), EAST = X mayor (hi_x)
    switch(dir)
    {
        case NAV_DIR_NORTH: fLoY += fAmount;
        case NAV_DIR_SOUTH: fHiY += fAmount;
        case NAV_DIR_EAST:  fHiX += fAmount;
        case NAV_DIR_WEST:  fLoX += fAmount;
    }
    
    // Validar que el área no se invierta
    if(fLoX >= fHiX || fLoY >= fHiY)
        return false;
    
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] = _:fLoX;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] = _:fLoY;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X] = _:fHiX;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y] = _:fHiY;
    
    // Recalcular centro
    sArea[NAV_AREA_CENTER_X] = (fLoX + fHiX) / 2.0;
    sArea[NAV_AREA_CENTER_Y] = (fLoY + fHiY) / 2.0;
    
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    return true;
}

// ============================================================================
// Internal Functions - Saving
// ============================================================================

bool:SaveNavmeshInternal(const szMapName[])
{
    new szFilePath[128];
    formatex(szFilePath, charsmax(szFilePath), "maps/%s.nav", szMapName);
    
    new iFile = fopen(szFilePath, "wb");
    if(!iFile)
    {
        log_amx("[NavMesh] Error: Cannot create file %s", szFilePath);
        return false;
    }
    
    // Write magic number
    WriteInt32(iFile, NAV_MAGIC_NUMBER);
    
    // Write version
    WriteInt32(iFile, NAV_VERSION);
    
    // Write BSP size (0 for now, not critical)
    WriteInt32(iFile, 0);
    
    // Save Place Directory
    SavePlaceDirectory(iFile);
    
    // Count valid areas (not deleted)
    new iValidCount = 0;
    new iTotal = ArraySize(g_aNavAreas);
    for(new i = 0; i < iTotal; i++)
    {
        new sArea[NavArea];
        ArrayGetArray(g_aNavAreas, i, sArea);
        if(sArea[NAV_AREA_ID] != 0)
            iValidCount++;
    }
    
    // Write area count
    WriteInt32(iFile, iValidCount);
    
    // Save each area
    for(new i = 0; i < iTotal; i++)
    {
        new sArea[NavArea];
        ArrayGetArray(g_aNavAreas, i, sArea);
        
        if(sArea[NAV_AREA_ID] == 0) // Deleted area
            continue;
        
        SaveArea(iFile, sArea);
    }
    
    fclose(iFile);
    
    log_amx("[NavMesh] Saved %d areas to %s", iValidCount, szFilePath);
    return true;
}

SavePlaceDirectory(iFile)
{
    if(g_nPlace[NAV_PLACE_NAMES] == Invalid_Array)
    {
        WriteInt16(iFile, 0); // No places
        return;
    }
    
    new iCount = ArraySize(g_nPlace[NAV_PLACE_NAMES]);
    WriteInt16(iFile, iCount);
    
    for(new i = 0; i < iCount; i++)
    {
        new szName[32];
        ArrayGetString(g_nPlace[NAV_PLACE_NAMES], i, szName, charsmax(szName));
        
        new iLen = strlen(szName);
        WriteInt16(iFile, iLen);
        
        for(new j = 0; j < iLen; j++)
        {
            WriteUint8(iFile, szName[j]);
        }
    }
}

SaveArea(iFile, const sArea[NavArea])
{
    // ID
    WriteInt32(iFile, sArea[NAV_AREA_ID]);
    
    // Attributes
    WriteUint8(iFile, _:sArea[NAV_AREA_ATTRIBUTES]);
    
    // Extent (6 floats)
    for(new i = 0; i < 6; i++)
    {
        WriteFloat(iFile, Float:sArea[NAV_AREA_EXTENT + i]);
    }
    
    // Corner heights
    WriteFloat(iFile, Float:sArea[NAV_AREA_NE_Z]);
    WriteFloat(iFile, Float:sArea[NAV_AREA_SW_Z]);
    
    // Connections by direction
    new iTotalConns = 0;
    for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
    {
        new Array:aConnect = GetAreaConnectArrayConst(sArea, dir);
        new iCount = (aConnect != Invalid_Array) ? ArraySize(aConnect) : 0;
        iTotalConns += iCount;
        
        WriteInt32(iFile, iCount);
        
        for(new i = 0; i < iCount; i++)
        {
            new sConnect[NavConnect];
            ArrayGetArray(aConnect, i, sConnect);
            WriteInt32(iFile, sConnect[NAV_CONNECT_ID]);
        }
    }
    
    // Hiding spots (0 - we don't save them)
    WriteUint8(iFile, 0);
    
    // Approach areas
    WriteUint8(iFile, sArea[NAV_AREA_APPROACH_COUNT]);
    
    if(sArea[NAV_AREA_APPROACH] != Invalid_Array)
    {
        for(new i = 0; i < sArea[NAV_AREA_APPROACH_COUNT]; i++)
        {
            new sApproach[NavApproachInfo];
            ArrayGetArray(sArea[NAV_AREA_APPROACH], i, sApproach);
            
            WriteInt32(iFile, sApproach[NAV_APPROACH_HERE_ID]);
            WriteInt32(iFile, sApproach[NAV_APPROACH_PREV_ID]);
            WriteUint8(iFile, _:sApproach[NAV_APPROACH_PREV_TO_HERE_HOW]);
            WriteInt32(iFile, sApproach[NAV_APPROACH_NEXT_ID]);
            WriteUint8(iFile, _:sApproach[NAV_APPROACH_HERE_TO_NEXT_HOW]);
        }
    }
    
    // Encounter spots (0 - we don't save them)
    WriteInt32(iFile, 0);
    
    // Place entry
    WriteInt16(iFile, sArea[NAV_AREA_PLACE]);
}

Array:GetAreaConnectArrayConst(const sArea[NavArea], NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: return sArea[NAV_AREA_CONNECT_NORTH];
        case NAV_DIR_EAST:  return sArea[NAV_AREA_CONNECT_EAST];
        case NAV_DIR_SOUTH: return sArea[NAV_AREA_CONNECT_SOUTH];
        case NAV_DIR_WEST:  return sArea[NAV_AREA_CONNECT_WEST];
    }
    return Invalid_Array;
}

// Binary write functions
WriteInt32(iFile, iValue)
{
    fwrite(iFile, iValue, BLOCK_INT);
}

WriteInt16(iFile, iValue)
{
    fwrite(iFile, iValue, BLOCK_SHORT);
}

WriteUint8(iFile, iValue)
{
    fwrite(iFile, iValue, BLOCK_BYTE);
}

WriteFloat(iFile, Float:fValue)
{
    fwrite(iFile, _:fValue, BLOCK_INT);
}

// ============================================================================
// Natives - Split, Merge, Splice
// ============================================================================

public native_split_area(plugin_id, num_params)
{
    new iAreaIndex = get_param(1);
    new NavDirType:splitDir = NavDirType:get_param(2);
    new Float:fSplitPos = get_param_f(3);
    
    return SplitAreaInternal(iAreaIndex, splitDir, fSplitPos);
}

public native_merge_areas(plugin_id, num_params)
{
    new iArea1 = get_param(1);
    new iArea2 = get_param(2);
    
    return MergeAreasInternal(iArea1, iArea2);
}

public native_splice_areas(plugin_id, num_params)
{
    new iArea1 = get_param(1);
    new iArea2 = get_param(2);
    
    return SpliceAreasInternal(iArea1, iArea2);
}

// Splits an area in two along a direction
SplitAreaInternal(iAreaIndex, NavDirType:splitDir, Float:fSplitPos)
{
    if(!IsValidAreaIndex(iAreaIndex))
        return Invalid_Area;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    new Float:fLoZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z];
    new Float:fHiZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z];
    
    new Float:vNewMins[3], Float:vNewMaxs[3];
    
    // Split according to direction
    if(splitDir == NAV_DIR_NORTH || splitDir == NAV_DIR_SOUTH)
    {
        // Horizontal split (along Y axis)
        if(fSplitPos <= fLoY || fSplitPos >= fHiY)
            return Invalid_Area;
        
        // Modify original area (south part)
        sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y] = _:fSplitPos;
        sArea[NAV_AREA_CENTER_Y] = (fLoY + fSplitPos) / 2.0;
        ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
        
        // Create new area (north part)
        vNewMins[0] = fLoX; vNewMins[1] = fSplitPos; vNewMins[2] = fLoZ;
        vNewMaxs[0] = fHiX; vNewMaxs[1] = fHiY; vNewMaxs[2] = fHiZ;
    }
    else
    {
        // Vertical split (along X axis)
        if(fSplitPos <= fLoX || fSplitPos >= fHiX)
            return Invalid_Area;
        
        // Modify original area (west part)
        sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X] = _:fSplitPos;
        sArea[NAV_AREA_CENTER_X] = (fLoX + fSplitPos) / 2.0;
        ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
        
        // Create new area (east part)
        vNewMins[0] = fSplitPos; vNewMins[1] = fLoY; vNewMins[2] = fLoZ;
        vNewMaxs[0] = fHiX; vNewMaxs[1] = fHiY; vNewMaxs[2] = fHiZ;
    }
    
    // Create the new area
    new iNewArea = CreateAreaInternal(vNewMins, vNewMaxs);
    
    if(iNewArea != Invalid_Area)
    {
        // Copy attributes
        new sNewArea[NavArea];
        ArrayGetArray(g_aNavAreas, iNewArea, sNewArea);
        sNewArea[NAV_AREA_ATTRIBUTES] = sArea[NAV_AREA_ATTRIBUTES];
        sNewArea[NAV_AREA_PLACE] = sArea[NAV_AREA_PLACE];
        ArraySetArray(g_aNavAreas, iNewArea, sNewArea);
        
        // Connect both areas bidirectionally
        ConnectAreasInternal(iAreaIndex, iNewArea, splitDir);
        ConnectAreasInternal(iNewArea, iAreaIndex, Navmesh_OppositeDirection(splitDir));
    }
    
    return iNewArea;
}

// Merges two adjacent areas into one
MergeAreasInternal(iArea1, iArea2)
{
    if(!IsValidAreaIndex(iArea1) || !IsValidAreaIndex(iArea2))
        return Invalid_Area;
    
    if(iArea1 == iArea2)
        return Invalid_Area;
    
    new sArea1[NavArea], sArea2[NavArea];
    ArrayGetArray(g_aNavAreas, iArea1, sArea1);
    ArrayGetArray(g_aNavAreas, iArea2, sArea2);
    
    // Calculate new combined extent
    new Float:fLoX = floatmin(Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_X], Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_LO_X]);
    new Float:fLoY = floatmin(Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y], Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y]);
    new Float:fLoZ = floatmin(Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z], Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z]);
    new Float:fHiX = floatmax(Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_X], Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_HI_X]);
    new Float:fHiY = floatmax(Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y], Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y]);
    new Float:fHiZ = floatmax(Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z], Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z]);
    
    // Update area 1 with new extent
    sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] = _:fLoX;
    sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] = _:fLoY;
    sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z] = _:fLoZ;
    sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_X] = _:fHiX;
    sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y] = _:fHiY;
    sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z] = _:fHiZ;
    
    // Recalculate center
    sArea1[NAV_AREA_CENTER_X] = (fLoX + fHiX) / 2.0;
    sArea1[NAV_AREA_CENTER_Y] = (fLoY + fHiY) / 2.0;
    sArea1[NAV_AREA_CENTER_Z] = (fLoZ + fHiZ) / 2.0;
    
    // Combine attributes
    sArea1[NAV_AREA_ATTRIBUTES] = NavAttributeType:(sArea1[NAV_AREA_ATTRIBUTES] | sArea2[NAV_AREA_ATTRIBUTES]);
    
    ArraySetArray(g_aNavAreas, iArea1, sArea1);
    
    // Transfer connections from area2 to area1 (except connections between them)
    for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
    {
        new Array:aConns = GetAreaConnectArray(sArea2, dir);
        if(aConns != Invalid_Array)
        {
            for(new i = 0; i < ArraySize(aConns); i++)
            {
                new sConn[NavConnect];
                ArrayGetArray(aConns, i, sConn);
                
                if(sConn[NAV_CONNECT_AREA] != iArea1)
                {
                    ConnectAreasInternal(iArea1, sConn[NAV_CONNECT_AREA], dir);
                }
            }
        }
    }
    
    // Delete area 2
    DeleteAreaInternal(iArea2);
    
    return iArea1;
}

// Creates an area between two unconnected areas
// Based on CNavArea::SpliceEdit from ReGameDLL_CS
// Uses 4 corners with interpolated heights to create proper ramps
SpliceAreasInternal(iArea1, iArea2)
{
    if(!IsValidAreaIndex(iArea1) || !IsValidAreaIndex(iArea2))
        return Invalid_Area;
    
    if(iArea1 == iArea2)
        return Invalid_Area;
    
    new sArea1[NavArea], sArea2[NavArea];
    ArrayGetArray(g_aNavAreas, iArea1, sArea1);
    ArrayGetArray(g_aNavAreas, iArea2, sArea2);
    
    // Extents of both areas
    new Float:fLo1X = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLo1Y = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHi1X = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHi1Y = Float:sArea1[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    new Float:fLo2X = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLo2Y = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHi2X = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHi2Y = Float:sArea2[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    // 4 corners of the new area
    new Float:vNW[3], Float:vNE[3], Float:vSE[3], Float:vSW[3];
    new NavDirType:dir1to2, NavDirType:dir2to1;
    new iNewArea = Invalid_Area;
    
    if(fLo1X > fHi2X)
    {
        // 'area1' is EAST of 'area2'
        new Float:fTop = floatmax(fLo1Y, fLo2Y);
        new Float:fBottom = floatmin(fHi1Y, fHi2Y);
        
        if(fTop >= fBottom)
            return Invalid_Area;
        
        // NW and SW are in area2 (west), NE and SE are in area1 (east)
        vNW[0] = fHi2X; vNW[1] = fTop;
        vNW[2] = GetAreaZInternal(sArea2, vNW[0], vNW[1]);
        
        vNE[0] = fLo1X; vNE[1] = fTop;
        vNE[2] = GetAreaZInternal(sArea1, vNE[0], vNE[1]);
        
        vSE[0] = fLo1X; vSE[1] = fBottom;
        vSE[2] = GetAreaZInternal(sArea1, vSE[0], vSE[1]);
        
        vSW[0] = fHi2X; vSW[1] = fBottom;
        vSW[2] = GetAreaZInternal(sArea2, vSW[0], vSW[1]);
        
        dir1to2 = NAV_DIR_WEST;
        dir2to1 = NAV_DIR_EAST;
    }
    else if(fHi1X < fLo2X)
    {
        // 'area1' is WEST of 'area2'
        new Float:fTop = floatmax(fLo1Y, fLo2Y);
        new Float:fBottom = floatmin(fHi1Y, fHi2Y);
        
        if(fTop >= fBottom)
            return Invalid_Area;
        
        // NW and SW are in area1 (west), NE and SE are in area2 (east)
        vNW[0] = fHi1X; vNW[1] = fTop;
        vNW[2] = GetAreaZInternal(sArea1, vNW[0], vNW[1]);
        
        vNE[0] = fLo2X; vNE[1] = fTop;
        vNE[2] = GetAreaZInternal(sArea2, vNE[0], vNE[1]);
        
        vSE[0] = fLo2X; vSE[1] = fBottom;
        vSE[2] = GetAreaZInternal(sArea2, vSE[0], vSE[1]);
        
        vSW[0] = fHi1X; vSW[1] = fBottom;
        vSW[2] = GetAreaZInternal(sArea1, vSW[0], vSW[1]);
        
        dir1to2 = NAV_DIR_EAST;
        dir2to1 = NAV_DIR_WEST;
    }
    else if(fLo1Y > fHi2Y)
    {
        // 'area1' is SOUTH of 'area2'
        new Float:fLeft = floatmax(fLo1X, fLo2X);
        new Float:fRight = floatmin(fHi1X, fHi2X);
        
        if(fLeft >= fRight)
            return Invalid_Area;
        
        // NW and NE are in area2 (north), SW and SE are in area1 (south)
        vNW[0] = fLeft; vNW[1] = fHi2Y;
        vNW[2] = GetAreaZInternal(sArea2, vNW[0], vNW[1]);
        
        vNE[0] = fRight; vNE[1] = fHi2Y;
        vNE[2] = GetAreaZInternal(sArea2, vNE[0], vNE[1]);
        
        vSE[0] = fRight; vSE[1] = fLo1Y;
        vSE[2] = GetAreaZInternal(sArea1, vSE[0], vSE[1]);
        
        vSW[0] = fLeft; vSW[1] = fLo1Y;
        vSW[2] = GetAreaZInternal(sArea1, vSW[0], vSW[1]);
        
        dir1to2 = NAV_DIR_NORTH;
        dir2to1 = NAV_DIR_SOUTH;
    }
    else if(fHi1Y < fLo2Y)
    {
        // 'area1' is NORTH of 'area2'
        new Float:fLeft = floatmax(fLo1X, fLo2X);
        new Float:fRight = floatmin(fHi1X, fHi2X);
        
        if(fLeft >= fRight)
            return Invalid_Area;
        
        // NW and NE are in area1 (north), SW and SE are in area2 (south)
        vNW[0] = fLeft; vNW[1] = fHi1Y;
        vNW[2] = GetAreaZInternal(sArea1, vNW[0], vNW[1]);
        
        vNE[0] = fRight; vNE[1] = fHi1Y;
        vNE[2] = GetAreaZInternal(sArea1, vNE[0], vNE[1]);
        
        vSE[0] = fRight; vSE[1] = fLo2Y;
        vSE[2] = GetAreaZInternal(sArea2, vSE[0], vSE[1]);
        
        vSW[0] = fLeft; vSW[1] = fLo2Y;
        vSW[2] = GetAreaZInternal(sArea2, vSW[0], vSW[1]);
        
        dir1to2 = NAV_DIR_SOUTH;
        dir2to1 = NAV_DIR_NORTH;
    }
    else
    {
        // Areas overlap - cannot create splice
        return Invalid_Area;
    }
    
    // Create area with 4 corners (allows ramps)
    iNewArea = CreateAreaWithCornersInternal(vNW, vNE, vSE, vSW);
    
    if(iNewArea != Invalid_Area)
    {
        // Connect bidirectionally
        ConnectAreasInternal(iArea1, iNewArea, dir1to2);
        ConnectAreasInternal(iNewArea, iArea1, Navmesh_OppositeDirection(dir1to2));
        
        ConnectAreasInternal(iArea2, iNewArea, dir2to1);
        ConnectAreasInternal(iNewArea, iArea2, Navmesh_OppositeDirection(dir2to1));
        
        // Inherit place if both areas have the same
        if(sArea1[NAV_AREA_PLACE] == sArea2[NAV_AREA_PLACE])
        {
            new sNewArea[NavArea];
            ArrayGetArray(g_aNavAreas, iNewArea, sNewArea);
            sNewArea[NAV_AREA_PLACE] = sArea1[NAV_AREA_PLACE];
            ArraySetArray(g_aNavAreas, iNewArea, sNewArea);
        }
    }
    
    return iNewArea;
}