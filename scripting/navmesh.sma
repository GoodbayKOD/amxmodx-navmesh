#include <amxmodx>
#include <fakemeta>
#include <file>
#include <xs>

#include <nav/navmesh_const>
#include <nav/navmesh_stocks>

#define nullptr     0

// ============================================================================
// Plugin Constants
// ============================================================================
const MAX_APPROACH_AREAS = 16;  // Maximum approach areas per area

// Macros
#define ComputeHashKey(%1)      (%1 & 0xFF)

// Binary write
#define WriteInt32(%1,%2)       fwrite(%1, %2, BLOCK_INT)
#define WriteInt16(%1,%2)       fwrite(%1, %2, BLOCK_SHORT)
#define WriteUint8(%1,%2)       fwrite(%1, %2, BLOCK_BYTE)
#define WriteFloat(%1,%2)       fwrite(%1, _:%2, BLOCK_INT)

// ============================================================================
// Var handlers
// ============================================================================
new Array:g_aNavAreas;      // Dynamic array of NavArea
new Array:g_aNavLadders;    // Dynamic array of NavLadder

// ============================================================================
// Var structures
// ============================================================================
new g_nGrid[NavAreaGrid];           // Spatial grid for fast search
new g_nPlace[NavPlaceDirectory];    // Place names directory

// ============================================================================
// Vars miscellaneos
// ============================================================================
new bool:g_bNavLoaded;  // Navmesh load state
new g_iNavAreaCount;    // Number of loaded areas
new g_iNextAreaID = 1;  // Next available ID for new areas

// ============================================================================
// Plugin Data
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
    register_native("Navmesh_GetAdjacentCount", "native_get_adjacent_count");
    register_native("Navmesh_GetAdjacentArea", "native_get_adjacent_area");
    register_native("Navmesh_IsConnected", "native_is_connected");
    register_native("Navmesh_BuildPathFromArea", "native_build_path_from_area");
    register_native("Navmesh_BuildPath", "native_build_path");
    register_native("Navmesh_GetPathLength", "native_get_path_length");
    register_native("Navmesh_GetPathSegment", "native_get_path_segment");
    register_native("Navmesh_ClearPath", "native_clear_path");
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
    register_plugin("Navmesh System", "1.0", "Goodbay");
}

public plugin_end()
{
    // Just in case is loaded
    if(g_bNavLoaded)
        UnloadInternal();
}

// ============================================================================
// Natives - Management
// ============================================================================
public NavErrorType:native_load(const pPluginID, const iParams)
{
    new szCurrentMap[32];
    get_string(1, szCurrentMap, charsmax(szCurrentMap));
    
    return LoadInternal(szCurrentMap);
}

public native_unload(const pPluginID, const iParams)
{
    if(g_bNavLoaded)
        UnloadInternal();
}

public bool:native_init(const pPluginID, const iParams)         { return InitEmpty(); }
public bool:native_is_loaded(const pPluginID, const iParams)    { return g_bNavLoaded; }
public native_get_area_count(const pPluginID, const iParams)    { return g_iNavAreaCount; }

// ============================================================================
// Natives - Area Search
// ============================================================================
public native_get_nearest_area(const pPluginID, const iParams)
{
    enum { arg_origin = 1, arg_maxdist, arg_beneath_limit };

    new Float:vOrigin[3];
    get_array_f(arg_origin, vOrigin, 3);
    
    return GetNearestAreaInternal(vOrigin, get_param_f(arg_maxdist), get_param_f(arg_beneath_limit));
}

public native_get_area_by_id(const pPluginID, const iParams)
{
    // Uses hash search O(1) instead of linear O(n)
    return FindAreaByID(get_param(1));
}

public native_get_area_id(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return 0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return sArea[NAV_AREA_ID];
}

// ============================================================================
// Natives - Area Information
// ============================================================================
public bool:native_get_area_center(const pPluginID, const iParams)
{
    enum { arg_areaindex = 1, arg_centerout };

    new iAreaIndex = get_param(arg_areaindex);
    
    if(!IsValidArea(iAreaIndex))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:vCenter[3];
    vCenter[0] = sArea[NAV_AREA_CENTER_X];
    vCenter[1] = sArea[NAV_AREA_CENTER_Y];
    vCenter[2] = sArea[NAV_AREA_CENTER_Z];
    
    set_array_f(arg_centerout, vCenter, 3);
    return true;
}

public bool:native_get_area_extent(const pPluginID, const iParams)
{
    enum { arg_areaindex = 1, arg_extend_lo, arg_extend_hi };

    new iAreaIndex = get_param(arg_areaindex);

    if(!IsValidArea(iAreaIndex))
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
    
    set_array_f(arg_extend_lo, vMins, 3);
    set_array_f(arg_extend_hi, vMaxs, 3);
    return true;
}

public NavAttributeType:native_get_area_attributes(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return NavAttributeType:0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    return NavAttributeType:sArea[NAV_AREA_ATTRIBUTES];
}

public bool:native_is_point_in_area(const pPluginID, const iParams)
{
    enum { arg_areaindex = 1, arg_pointout };

    new iAreaIndex = get_param(arg_areaindex);
    
    if(!IsValidArea(iAreaIndex))
        return false;
    
    new Float:vPoint[3];
    get_array_f(arg_pointout, vPoint, 3);
    
    return IsPointInAreaInternalZInternal(iAreaIndex, vPoint);
}

public Float:native_get_area_z(const pPluginID, const iParams)
{
    enum { arg_areaindex = 1, arg_x, arg_y };

    new iAreaIndex = get_param(arg_areaindex);
    
    if(!IsValidArea(iAreaIndex))
        return 0.0;
    
    return NavGetAreaZInternal(iAreaIndex, get_param_f(arg_x), get_param_f(arg_y));
}

// ============================================================================
// Natives - Connections
// ============================================================================
public native_get_adjacent_count(const pPluginID, const iParams)
{
    enum { arg_areaindex = 1, arg_dir };

    new iAreaIndex      = get_param(arg_areaindex);
    new NavDirType:dir  = NavDirType:get_param(arg_dir);
    
    if(!IsValidArea(iAreaIndex) || dir >= NUM_NAV_DIRECTIONS)
        return 0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Array:aConnect = GetAreaConnectArray(sArea, dir);
    return (aConnect != Invalid_Array ? ArraySize(aConnect) : 0);
}

public native_get_adjacent_area(const pPluginID, const iParams)
{
    enum { arg_areaindex = 1, arg_dir, arg_index };

    new iAreaIndex      = get_param(arg_areaindex);
    new NavDirType:dir  = NavDirType:get_param(arg_dir);
    new iIndex          = get_param(arg_index);
    
    if(!IsValidArea(iAreaIndex) || dir >= NUM_NAV_DIRECTIONS)
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

public bool:native_is_connected(const pPluginID, const iParams)
{
    enum { arg_areaindex_1 = 1, arg_areaindex_2, arg_dir };

    new iAreaIndex1         = get_param(arg_areaindex_1);
    new iAreaIndex2         = get_param(arg_areaindex_2);
    new NavDirType:dir      = NavDirType:get_param(arg_dir);
    
    if(!IsValidArea(iAreaIndex1) || !IsValidArea(iAreaIndex2))
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
public bool:native_build_path_from_area(const pPluginID, const iParams)
{
    enum { arg_startarea = 1, arg_goalarea, arg_pathout };

    new iStartArea      = get_param(arg_startarea);
    new iGoalArea       = get_param(arg_goalarea);
    new Array:aPathOut  = Array:get_param(arg_pathout);
    
    if(!IsValidArea(iStartArea) || !IsValidArea(iGoalArea))
        return false;
    
    if(aPathOut == Invalid_Array)
        return false;
    
    ArrayClear(aPathOut);
    return BuildPathAStar(iStartArea, iGoalArea, aPathOut);
}

public bool:native_build_path(const pPluginID, const iParams)
{
    enum { arg_start = 1, arg_goal, arg_pathout };

    new Float:vStart[3], Float:vGoal[3];
    get_array_f(arg_start, vStart, 3);
    get_array_f(arg_goal, vGoal, 3);

    new Array:aPathOut = Array:get_param(arg_pathout);
    if(aPathOut == Invalid_Array)
        return false;
    
    // Find nearest areas
    new iStartArea  = GetNearestAreaInternal(vStart, 500.0, 120.0);
    new iGoalArea   = GetNearestAreaInternal(vGoal, 500.0, 120.0);
    
    if(iStartArea == Invalid_Area || iGoalArea == Invalid_Area)
        return false;
    
    ArrayClear(aPathOut);
    return BuildPathAStar(iStartArea, iGoalArea, aPathOut);
}

public native_get_path_length(const pPluginID, const iParams)
{
    new Array:aPath = Array:get_param(1);
    return aPath != Invalid_Array ? ArraySize(aPath) : 0;
}

public bool:native_get_path_segment(const pPluginID, const iParams)
{
    enum { arg_path = 1, arg_pathindex, arg_positionout, arg_how, arg_area };

    new Array:aPath = Array:get_param(arg_path);
    new iIndex = get_param(arg_pathindex);
    
    if(aPath == Invalid_Array || iIndex < 0 || iIndex >= ArraySize(aPath))
        return false;
    
    new sSegment[NavPathSegment];
    ArrayGetArray(aPath, iIndex, sSegment);
    
    new Float:vPosition[3];
    vPosition[0] = sSegment[NAV_PATH_POS_X];
    vPosition[1] = sSegment[NAV_PATH_POS_Y];
    vPosition[2] = sSegment[NAV_PATH_POS_Z];
    
    set_array_f(arg_positionout, vPosition, 3);
    set_param_byref(arg_how, _:sSegment[NAV_PATH_HOW]);
    set_param_byref(arg_area, sSegment[NAV_PATH_AREA]);
    return true;
}

public native_clear_path(const pPluginID, const iParams)
{
    new Array:aPath = Array:get_param(1);

    if(aPath != Invalid_Array)
        ArrayClear(aPath);
}

// ============================================================================
// Natives - Utilities
// ============================================================================
public bool:native_get_closest_point_in_area(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return false;
    
    new Float:vPos[3], Float:vClose[3];
    get_array_f(2, vPos, 3);
    
    GetClosestPointInArea(iAreaIndex, vPos, vClose);
    
    set_array_f(3, vClose, 3);
    return true;
}

public Float:native_get_distance_squared_to_area(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return 0.0;
    
    new Float:vPos[3];
    get_array_f(2, vPos, 3);
    
    return GetDistanceSquaredToArea(iAreaIndex, vPos);
}

public native_get_random_area(const pPluginID, const iParams)
{
    if(!g_bNavLoaded || g_iNavAreaCount == 0)
        return Invalid_Area;
    
    return random_num(0, g_iNavAreaCount - 1);
}

public bool:native_get_random_position_in_area(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return false;
    
    new Float:vPos[3];
    GetRandomPositionInArea(iAreaIndex, vPos);
    
    set_array_f(2, vPos, 3);
    return true;
}

// ============================================================================
// Natives - Additional Functions
// ============================================================================

public bool:native_get_area_corner(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    new NavCornerType:corner = NavCornerType:get_param(2);
    
    if(!IsValidArea(iAreaIndex) || corner >= NUM_NAV_CORNERS)
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:vPos[3];
    GetAreaCorner(sArea, corner, vPos);
    
    set_array_f(3, vPos, 3);
    return true;
}

public bool:native_is_area_overlapping(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return false;
    
    new Float:vPos[3];
    get_array_f(2, vPos, 3);
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    return IsOverlappingPoint(sArea, vPos);
}

public bool:native_are_areas_overlapping(const pPluginID, const iParams)
{
    new iAreaIndex1 = get_param(1);
    new iAreaIndex2 = get_param(2);
    
    if(!IsValidArea(iAreaIndex1) || !IsValidArea(iAreaIndex2))
        return false;
    
    new sArea1[NavArea], sArea2[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex1, sArea1);
    ArrayGetArray(g_aNavAreas, iAreaIndex2, sArea2);
    
    return AreAreasOverlapping(sArea1, sArea2);
}

public bool:native_compute_portal(const pPluginID, const iParams)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidArea(iFromArea) || !IsValidArea(iToArea))
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

public bool:native_compute_closest_point_in_portal(const pPluginID, const iParams)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidArea(iFromArea) || !IsValidArea(iToArea))
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

public native_get_area_place(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return UNDEFINED_PLACE;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return sArea[NAV_AREA_PLACE];
}

public bool:native_get_place_name(const pPluginID, const iParams)
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

public native_get_approach_count(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return 0;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    return sArea[NAV_AREA_APPROACH_COUNT];
}

public bool:native_get_approach_info(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    new iApproachIndex = get_param(2);
    
    if(!IsValidArea(iAreaIndex))
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

public native_get_ladder_count(const pPluginID, const iParams)
{
    if(g_aNavLadders == Invalid_Array)
        return 0;
    
    return ArraySize(g_aNavLadders);
}

public bool:native_get_ladder_info(const pPluginID, const iParams)
{
    new iLadderIndex = get_param(1);
    
    if(g_aNavLadders == Invalid_Array || iLadderIndex < 0 || iLadderIndex >= ArraySize(g_aNavLadders))
        return false;
    
    new sLadder[NavLadder];
    ArrayGetArray(g_aNavLadders, iLadderIndex, sLadder);
    
    new Float:vTop[3], Float:vBottom[3];
    vTop[0] = sLadder[NAV_LADDER_TOP_X];
    vTop[1] = sLadder[NAV_LADDER_TOP_Y];
    vTop[2] = sLadder[NAV_LADDER_TOP_Z];
    vBottom[0] = sLadder[NAV_LADDER_BOTTOM_X];
    vBottom[1] = sLadder[NAV_LADDER_BOTTOM_Y];
    vBottom[2] = sLadder[NAV_LADDER_BOTTOM_Z];
    
    set_array_f(2, vTop, 3);
    set_array_f(3, vBottom, 3);
    set_param_byref(4, _:sLadder[NAV_LADDER_LENGTH]);
    set_param_byref(5, _:sLadder[NAV_LADDER_DIR]);
    return true;
}

// ============================================================================
// Internal Functions - Loading
// ============================================================================
public NavErrorType:LoadInternal(const szMapName[])
{
    // If already loaded, unload first
    if(g_bNavLoaded)
        UnloadInternal();
    
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
            UnloadInternal();
            return NAV_CORRUPT_DATA;
        }
    }
    
    // Read area count
    if(!FileReadInt32(iFile, g_iNavAreaCount))
    {
        log_amx("[NavMesh] Failed to read area count");
        fclose(iFile);
        UnloadInternal();
        return NAV_CORRUPT_DATA;
    }
    
    if(g_iNavAreaCount == 0)
    {
        log_amx("[NavMesh] No areas in file");
        fclose(iFile);
        UnloadInternal();
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
            UnloadInternal();
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

public UnloadInternal()
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

public bool:InitEmpty()
{
    // If navmesh already loaded, unload first
    if(g_bNavLoaded)
        UnloadInternal();
    
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

public bool:LoadPlaceDirectory(iFile)
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

public bool:LoadArea(iFile, iVersion)
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
    sArea[NAV_AREA_CONNECT_NORTH] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_EAST] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_SOUTH] = ArrayCreate(NavConnect);
    sArea[NAV_AREA_CONNECT_WEST] = ArrayCreate(NavConnect);
    
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
                log_amx("[NavMesh] Warning: Area %d has invalid connection to ID %d", sArea[NAV_AREA_ID], sConnect[NAV_CONNECT_ID]);
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

public InitGrid(Float:fMinX, Float:fMaxX, Float:fMinY, Float:fMaxY)
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

public AddAreaToGrid(iAreaIndex)
{
    // Don't use IsValidArea here because it can be called during loading
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

public RemoveAreaFromGrid(iAreaIndex)
{
    if(!IsValidArea(iAreaIndex))
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

// Fast search by ID using hash table
stock FindAreaByID(iAreaID)
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

public GetNearestAreaInternal(const Float:vOrigin[3], Float:fMaxDist, Float:fBeneathLimit)
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
            new Float:fAreaZ = NavGetAreaZInternal(i, vOrigin[0], vOrigin[1]);
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

stock bool:IsPointInAreaInternalZInternal(iAreaIndex, const Float:vPoint[3])
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
    new Float:fZ = NavGetAreaZInternal(iAreaIndex, vPoint[0], vPoint[1]);
    
    // Check if close to area floor
    return floatabs(vPoint[2] - fZ) < HALF_HUMAN_HEIGHT;
}

Float:NavGetAreaZInternal(iAreaIndex, Float:fX, Float:fY)
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
    new Float:fNEZ = Float:sArea[NAV_AREA_NE_Z];
    new Float:fSEZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z];
    new Float:fSWZ = Float:sArea[NAV_AREA_SW_Z];
    
    // Interpolation
    new Float:fNorthZ = fNWZ + fU * (fNEZ - fNWZ);
    new Float:fSouthZ = fSWZ + fU * (fSEZ - fSWZ);
    
    return fNorthZ + fV * (fSouthZ - fNorthZ);
}

// ============================================================================
// Utilities
// ============================================================================

stock bool:IsValidArea(iAreaIndex, bool:bDeleteCheck = true)
{
    if(!g_bNavLoaded || g_aNavAreas == Invalid_Array)
        return false;
    
    if(iAreaIndex < 0 || iAreaIndex >= ArraySize(g_aNavAreas))
        return false;
    
    // Verify area is not deleted
    if(bDeleteCheck)
    {
        new sArea[NavArea];
        ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);

        return (sArea[NAV_AREA_ID] != 0); 
    }
    
    return true;
}

stock Array:GetAreaConnectArray(const sArea[NavArea], NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: 
            return sArea[NAV_AREA_CONNECT_NORTH];
        case NAV_DIR_EAST:  
            return sArea[NAV_AREA_CONNECT_EAST];
        case NAV_DIR_SOUTH: 
            return sArea[NAV_AREA_CONNECT_SOUTH];
        case NAV_DIR_WEST:  
            return sArea[NAV_AREA_CONNECT_WEST];
    }

    return Invalid_Array;
}

// ============================================================================
// Pathfinding A*
// ============================================================================
public bool:BuildPathAStar(iStartArea, iGoalArea, Array:aPathOut)
{
    if(iStartArea == iGoalArea)
        return false;
    
    // Increment global marker
    static iMasterMarker = 1;
    iMasterMarker++;
    
    // Initialize start area
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iStartArea, sArea);
    sArea[NAV_AREA_COST_SO_FAR] = 0.0;
    sArea[NAV_AREA_TOTAL_COST] = Math_GetHeuristicCost(iStartArea, iGoalArea);
    sArea[NAV_AREA_PARENT] = Invalid_Area;
    sArea[NAV_AREA_MARKER] = iMasterMarker;
    sArea[NAV_AREA_OPEN_MARKER] = iMasterMarker;
    ArraySetArray(g_aNavAreas, iStartArea, sArea);
    
    // Simple open list (index array)
    new Array:aOpenList = ArrayCreate();
    ArrayPushCell(aOpenList, iStartArea);
    
    new bool:bPathFound = false;
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
                
                new sNeighbor[NavArea];
                ArrayGetArray(g_aNavAreas, iNeighborArea, sNeighbor);
                
                // Calculate new cost
                new Float:fNewCost = sArea[NAV_AREA_COST_SO_FAR] + Math_GetMoveCost(iCurrentArea, iNeighborArea);
                
                // If not visited or we found a better path
                if(sNeighbor[NAV_AREA_MARKER] != iMasterMarker || fNewCost < sNeighbor[NAV_AREA_COST_SO_FAR])
                {
                    sNeighbor[NAV_AREA_COST_SO_FAR] = fNewCost;
                    sNeighbor[NAV_AREA_TOTAL_COST] = fNewCost + Math_GetHeuristicCost(iNeighborArea, iGoalArea);
                    sNeighbor[NAV_AREA_PARENT] = iCurrentArea;
                    sNeighbor[NAV_AREA_MARKER] = iMasterMarker;
                    
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
    
    if(!bPathFound)
        return false;
    
    // Reconstruct path from goal to start
    new iCurrentArea = iGoalArea;
    new Array:aTempPath = ArrayCreate();
    
    while(iCurrentArea != Invalid_Area && iCurrentArea != iStartArea)
    {
        ArrayPushCell(aTempPath, iCurrentArea);
        
        ArrayGetArray(g_aNavAreas, iCurrentArea, sArea);
        iCurrentArea = sArea[NAV_AREA_PARENT];
    }
    
    ArrayPushCell(aTempPath, iStartArea);
    
    // Reverse path and create segments
    for(new i = ArraySize(aTempPath) - 1; i >= 0; i--)
    {
        new iArea = ArrayGetCell(aTempPath, i);
        new sSegment[NavPathSegment];
        
        ArrayGetArray(g_aNavAreas, iArea, sArea);
        
        sSegment[NAV_PATH_AREA] = iArea;
        
        // Calculate direction from previous area
        if(i > 0)
        {
            new iPrevArea = ArrayGetCell(aTempPath, i - 1);
            sSegment[NAV_PATH_HOW] = NavTraverseType:GetDirectionFromTo(iPrevArea, iArea);
        }
        else
        {
            sSegment[NAV_PATH_HOW] = NAV_TRAVERSE_NORTH;
        }
        
        sSegment[NAV_PATH_POS_X] = sArea[NAV_AREA_CENTER_X];
        sSegment[NAV_PATH_POS_Y] = sArea[NAV_AREA_CENTER_Y];
        sSegment[NAV_PATH_POS_Z] = sArea[NAV_AREA_CENTER_Z];
        
        ArrayPushArray(aPathOut, sSegment);
    }
    
    ArrayDestroy(aTempPath);
    
    return true;
}

stock PopLowestCostArea(Array:aOpenList)
{
    if(ArraySize(aOpenList) == 0)
        return Invalid_Area;
    
    new iLowestIndex, i, iArea;
    new Float:fLowestCost = 999999.9;
    new sArea[NavArea];
    
    for(i = 0; i < ArraySize(aOpenList); i++)
    {
        iArea = ArrayGetCell(aOpenList, i);
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

stock NavDirType:GetDirectionFromTo(iFromArea, iToArea)
{
    new sFrom[NavArea], sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    new Float:fDX = sTo[NAV_AREA_CENTER_X] - sFrom[NAV_AREA_CENTER_X];
    new Float:fDY = sTo[NAV_AREA_CENTER_Y] - sFrom[NAV_AREA_CENTER_Y];
    
    // Determine predominant direction
    if(floatabs(fDX) > floatabs(fDY))
        return (fDX > 0.0) ? NAV_DIR_EAST : NAV_DIR_WEST;
    else
        return (fDY > 0.0) ? NAV_DIR_SOUTH : NAV_DIR_NORTH;
}

// ============================================================================
// Geometry Helper Functions
// ============================================================================

stock GetClosestPointInArea(iAreaIndex, const Float:vPos[3], Float:vClose[3])
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
    vClose[2] = NavGetAreaZInternal(iAreaIndex, vClose[0], vClose[1]);
}

stock Float:GetDistanceSquaredToArea(iAreaIndex, const Float:vPos[3])
{
    new Float:vClose[3];
    GetClosestPointInArea(iAreaIndex, vPos, vClose);
    
    new Float:fDX = vPos[0] - vClose[0];
    new Float:fDY = vPos[1] - vClose[1];
    new Float:fDZ = vPos[2] - vClose[2];
    
    return fDX * fDX + fDY * fDY + fDZ * fDZ;
}

stock GetRandomPositionInArea(iAreaIndex, Float:vPos[3])
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
    vPos[2] = NavGetAreaZInternal(iAreaIndex, vPos[0], vPos[1]);
}

// ============================================================================
// Helper Functions - Corners and Portals
// ============================================================================
stock GetAreaCorner(const sArea[NavArea], NavCornerType:corner, Float:vPos[3])
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

stock bool:IsOverlappingPoint(const sArea[NavArea], const Float:vPos[3])
{
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    return (vPos[0] >= fLoX && vPos[0] <= fHiX && 
            vPos[1] >= fLoY && vPos[1] <= fHiY);
}

stock bool:AreAreasOverlapping(const sArea1[NavArea], const sArea2[NavArea])
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

stock ComputePortal(const sFrom[NavArea], const sTo[NavArea], NavDirType:dir, Float:vCenter[3], &Float:fHalfWidth)
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

stock ComputeClosestPointInPortal(const sFrom[NavArea], const sTo[NavArea], NavDirType:dir, const Float:vFromPos[3], Float:vClosePos[3])
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
public native_create_area(const pPluginID, const iParams)
{
    new Float:vMins[3], Float:vMaxs[3];
    get_array_f(1, vMins, 3);
    get_array_f(2, vMaxs, 3);
    
    return CreateAreaInternal(vMins, vMaxs);
}

public bool:native_delete_area(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    
    if(!IsValidArea(iAreaIndex))
        return false;
    
    return DeleteAreaInternal(iAreaIndex);
}

public bool:native_set_area_attributes(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    new NavAttributeType:attrs = NavAttributeType:get_param(2);
    
    if(!IsValidArea(iAreaIndex))
        return false;
    
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    sArea[NAV_AREA_ATTRIBUTES] = attrs;
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    
    return true;
}

public bool:native_connect_areas(const pPluginID, const iParams)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidArea(iFromArea) || !IsValidArea(iToArea))
        return false;
    
    return ConnectAreasInternal(iFromArea, iToArea, dir);
}

public bool:native_disconnect_areas(const pPluginID, const iParams)
{
    new iFromArea = get_param(1);
    new iToArea = get_param(2);
    new NavDirType:dir = NavDirType:get_param(3);
    
    if(!IsValidArea(iFromArea) || !IsValidArea(iToArea))
        return false;
    
    return DisconnectAreasInternal(iFromArea, iToArea, dir);
}

public bool:native_set_corner_z(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    new NavCornerType:corner = NavCornerType:get_param(2);
    new Float:fZ = get_param_f(3);
    
    if(!IsValidArea(iAreaIndex) || corner >= NUM_NAV_CORNERS)
        return false;
    
    return SetCornerZInternal(iAreaIndex, corner, fZ);
}

public bool:native_set_area_extent(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    new NavDirType:dir = NavDirType:get_param(2);
    new Float:fAmount = get_param_f(3);
    
    if(!IsValidArea(iAreaIndex) || dir >= NUM_NAV_DIRECTIONS)
        return false;
    
    return SetAreaExtentInternal(iAreaIndex, dir, fAmount);
}

public bool:native_save(const pPluginID, const iParams)
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
public CreateAreaWithCornersInternal(const Float:vNW[3], const Float:vNE[3], const Float:vSE[3], const Float:vSW[3])
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

public CreateAreaInternal(const Float:vMins[3], const Float:vMaxs[3])
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

public bool:DeleteAreaInternal(iAreaIndex)
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

stock RemoveAllConnectionsToArea(iTargetArea)
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

stock bool:ConnectAreasInternal(iFromArea, iToArea, NavDirType:dir)
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

stock bool:DisconnectAreasInternal(iFromArea, iToArea, NavDirType:dir)
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

stock bool:SetCornerZInternal(iAreaIndex, NavCornerType:corner, Float:fZ)
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    switch(corner)
    {
        case NAV_CORNER_NORTH_WEST:
            sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z] = _:fZ;
        case NAV_CORNER_NORTH_EAST:
            sArea[NAV_AREA_NE_Z] = _:fZ;
        case NAV_CORNER_SOUTH_EAST:
            sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z] = _:fZ;
        case NAV_CORNER_SOUTH_WEST:
            sArea[NAV_AREA_SW_Z] = _:fZ;
    }
    
    // Recalculate center Z
    new Float:fLoZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Z];
    new Float:fHiZ = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Z];

    sArea[NAV_AREA_CENTER_Z] = (fLoZ + fHiZ) / 2.0;
    
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    return true;
}

stock bool:SetAreaExtentInternal(iAreaIndex, NavDirType:dir, Float:fAmount)
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavAreas, iAreaIndex, sArea);
    
    new Float:fLoX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X];
    new Float:fLoY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y];
    new Float:fHiX = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X];
    new Float:fHiY = Float:sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y];
    
    // Ajust the side according to the direction
    // NORTH    = Y min (lo_y)    SOUTH = Y max (hi_y)
    // WEST     = X min (lo_x),   EAST  = X max (hi_x)
    switch(dir)
    {
        case NAV_DIR_NORTH: fLoY += fAmount;
        case NAV_DIR_SOUTH: fHiY += fAmount;
        case NAV_DIR_EAST:  fHiX += fAmount;
        case NAV_DIR_WEST:  fLoX += fAmount;
    }
    
    // Verify that the area is not inverted
    if(fLoX >= fHiX || fLoY >= fHiY)
        return false;
    
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_X] = _:fLoX;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_LO_Y] = _:fLoY;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_X] = _:fHiX;
    sArea[NAV_AREA_EXTENT + NAV_EXTENT_HI_Y] = _:fHiY;
    
    // Recalculate center
    sArea[NAV_AREA_CENTER_X] = (fLoX + fHiX) / 2.0;
    sArea[NAV_AREA_CENTER_Y] = (fLoY + fHiY) / 2.0;
    
    ArraySetArray(g_aNavAreas, iAreaIndex, sArea);
    return true;
}

// ============================================================================
// Internal Functions - Saving
// ============================================================================

public bool:SaveNavmeshInternal(const szMapName[])
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

public SaveArea(iFile, const sArea[NavArea])
{
    // ID
    WriteInt32(iFile, sArea[NAV_AREA_ID]);
    
    // Attributes
    WriteUint8(iFile, _:sArea[NAV_AREA_ATTRIBUTES]);
    
    // Extent (6 floats)
    for(new i = 0; i < 6; i++)
        WriteFloat(iFile, Float:sArea[NAV_AREA_EXTENT + i]);
    
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

stock SavePlaceDirectory(iFile)
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

stock Array:GetAreaConnectArrayConst(const sArea[NavArea], NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: 
            return sArea[NAV_AREA_CONNECT_NORTH];
        case NAV_DIR_EAST:  
            return sArea[NAV_AREA_CONNECT_EAST];
        case NAV_DIR_SOUTH: 
            return sArea[NAV_AREA_CONNECT_SOUTH];
        case NAV_DIR_WEST:  
            return sArea[NAV_AREA_CONNECT_WEST];
    }

    return Invalid_Array;
}

// ============================================================================
// Natives - Split, Merge, Splice
// ============================================================================
public native_split_area(const pPluginID, const iParams)
{
    new iAreaIndex = get_param(1);
    new NavDirType:splitDir = NavDirType:get_param(2);
    new Float:fSplitPos = get_param_f(3);
    
    return SplitAreaInternal(iAreaIndex, splitDir, fSplitPos);
}

public native_merge_areas(const pPluginID, const iParams)
{
    new iArea1 = get_param(1);
    new iArea2 = get_param(2);
    
    return MergeAreasInternal(iArea1, iArea2);
}

public native_splice_areas(const pPluginID, const iParams)
{
    new iArea1 = get_param(1);
    new iArea2 = get_param(2);
    
    return SpliceAreasInternal(iArea1, iArea2);
}

// Splits an area in two along a direction
stock SplitAreaInternal(iAreaIndex, NavDirType:splitDir, Float:fSplitPos)
{
    if(!IsValidArea(iAreaIndex))
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
stock MergeAreasInternal(iArea1, iArea2)
{
    if(!IsValidArea(iArea1) || !IsValidArea(iArea2))
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
stock SpliceAreasInternal(iArea1, iArea2)
{
    if(!IsValidArea(iArea1) || !IsValidArea(iArea2))
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

stock Float:Math_GetHeuristicCost(iFromArea, iToArea)
{
    new sFrom[NavArea], sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iFromArea, sFrom);
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    // 2D Euclidean distance
    new Float:fDX = sTo[NAV_AREA_CENTER_X] - sFrom[NAV_AREA_CENTER_X];
    new Float:fDY = sTo[NAV_AREA_CENTER_Y] - sFrom[NAV_AREA_CENTER_Y];
    
    return floatsqroot(fDX * fDX + fDY * fDY);
}

Float:Math_GetMoveCost(iFromArea, iToArea)
{
    // Base cost is distance
    new Float:fCost = Math_GetHeuristicCost(iFromArea, iToArea);
    
    // Add penalties for attributes
    new sTo[NavArea];
    ArrayGetArray(g_aNavAreas, iToArea, sTo);
    
    if(sTo[NAV_AREA_ATTRIBUTES] & NAV_ATTR_CROUCH)
        fCost *= 2.0; // Crouching is slower
    
    if(sTo[NAV_AREA_ATTRIBUTES] & NAV_ATTR_JUMP)
        fCost *= 1.5; // Jumping has extra cost
    
    return fCost;
}