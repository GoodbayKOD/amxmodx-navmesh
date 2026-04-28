/**
 * navmesh_const.inc
 * 
 * Constants, enumerations and structures for the navigation system
 * Based on ReGameDLL_CS nav.h / nav_area.h
 * 
 * @author Goodbay
 * @version 2.0
 */

#if defined _navmesh_const_included
    #endinput
#endif
#define _navmesh_const_included

// ============================================================================
// .nav format Version and Magic Number
// ============================================================================

#define NAV_VERSION         5
#define NAV_MAGIC_NUMBER    0xFEEDFACE

// ============================================================================
// Special values
// ============================================================================

#define Invalid_Area        -1
#define UNDEFINED_PLACE     0
#define ANY_PLACE           0xFFFF

// ============================================================================
// Block sizes for binary read/write
// ============================================================================

#define BLOCK_BYTE          1
#define BLOCK_SHORT         2
#define BLOCK_INT           4
#define BLOCK_FLOAT         4

// ============================================================================
// Navigation constants (based on ReGameDLL_CS)
// ============================================================================

stock Float:GENERATION_STEP_SIZE    = 25.0;     // Step size for grid generation
stock Float:STEP_HEIGHT             = 18.0;     // Maximum height to walk without jumping
stock Float:JUMP_HEIGHT             = 41.8;     // Maximum height to jump
stock Float:JUMP_CROUCH_HEIGHT      = 58.0;     // Maximum height to jump while crouching
stock Float:MAX_SLOPE               = 1.4;      // Maximum navigable slope
stock Float:MAX_UNIT_Z_SLOPE        = 0.7;      // Maximum Z component of normal

// ============================================================================
// Player dimensions
// ============================================================================

stock Float:BOT_RADIUS              = 10.0;     // Bot circular radius
stock Float:DEATH_DROP              = 200.0;    // Fatal fall height
stock Float:HALF_HUMAN_WIDTH        = 16.0;
stock Float:HALF_HUMAN_HEIGHT       = 36.0;
stock Float:HUMAN_HEIGHT            = 72.0;

// ============================================================================
// Spatial grid
// ============================================================================

stock Float:GRID_CELL_SIZE          = 300.0;    // Size of each grid cell

// ============================================================================
// Walk-through flags
// ============================================================================

#define WALK_THRU_DOORS         0x01
#define WALK_THRU_BREAKABLES    0x02
#define WALK_THRU_EVERYTHING    (WALK_THRU_DOORS | WALK_THRU_BREAKABLES)

// ============================================================================
// Enumerations
// ============================================================================

/**
 * .nav file load errors
 */
enum NavErrorType
{
    NAV_OK = 0,
    NAV_CANT_ACCESS_FILE,
    NAV_INVALID_FILE,
    NAV_BAD_FILE_VERSION,
    NAV_CORRUPT_DATA
};

/**
 * Area/node attributes
 */
enum NavAttributeType
{
    NAV_ATTR_CROUCH     = 0x01,     // Must crouch to use this area
    NAV_ATTR_JUMP       = 0x02,     // Must jump to traverse this area
    NAV_ATTR_PRECISE    = 0x04,     // Do not adjust for obstacles, move precisely
    NAV_ATTR_NO_JUMP    = 0x08,     //禁止 discontinuity jumps

    // Custom ones, for third party plugins
    NAV_ATTR_CUSTOM_1   = 0x10,
    NAV_ATTR_CUSTOM_2   = 0x20,
    NAV_ATTR_CUSTOM_3   = 0x40
};

/**
 * Cardinal directions
 */
enum NavDirType
{
    NAV_DIR_NORTH = 0,
    NAV_DIR_EAST,
    NAV_DIR_SOUTH,
    NAV_DIR_WEST,
    
    NUM_NAV_DIRECTIONS
};

/**
 * Traversal types between areas
 */
enum NavTraverseType
{
    // NOTE: The first 4 directions MUST match NavDirType
    NAV_TRAVERSE_NORTH = 0,
    NAV_TRAVERSE_EAST,
    NAV_TRAVERSE_SOUTH,
    NAV_TRAVERSE_WEST,
    NAV_TRAVERSE_LADDER_UP,
    NAV_TRAVERSE_LADDER_DOWN,
    NAV_TRAVERSE_JUMP,
    
    NUM_NAV_TRAVERSE_TYPES
};

/**
 * Result of UpdatePathMovement (mirrors CCSBot::PathResult)
 */
enum NavPathResult
{
    NAV_PATH_FAILURE = 0,
    NAV_PATH_PROGRESSING,
    NAV_PATH_END_OF_PATH
};

/**
 * Corners of an area
 */
enum NavCornerType
{
    NAV_CORNER_NORTH_WEST = 0,
    NAV_CORNER_NORTH_EAST,
    NAV_CORNER_SOUTH_EAST,
    NAV_CORNER_SOUTH_WEST,
    
    NUM_NAV_CORNERS
};

/**
 * Relative directions
 */
enum NavRelativeDirType
{
    NAV_RELATIVE_FORWARD = 0,
    NAV_RELATIVE_RIGHT,
    NAV_RELATIVE_BACKWARD,
    NAV_RELATIVE_LEFT,
    NAV_RELATIVE_UP,
    NAV_RELATIVE_DOWN,
    
    NUM_NAV_RELATIVE_DIRECTIONS
};

/**
 * Route types
 */
enum NavRouteType
{
    NAV_ROUTE_FASTEST = 0,
    NAV_ROUTE_SAFEST
};

// ============================================================================
// Data structures
// ============================================================================

/**
 * Extent - Bounds of an area in world coordinates
 */
enum _:NavExtent
{
    Float:NAV_EXTENT_LO_X,
    Float:NAV_EXTENT_LO_Y,
    Float:NAV_EXTENT_LO_Z,
    Float:NAV_EXTENT_HI_X,
    Float:NAV_EXTENT_HI_Y,
    Float:NAV_EXTENT_HI_Z
};

/**
 * NavConnect - Connection to an adjacent area
 */
enum _:NavConnect
{
    NAV_CONNECT_ID,         // ID of the connected area (used during loading)
    NAV_CONNECT_AREA        // Index of the area in the array (after PostLoad)
};

/**
 * ApproachInfo - Approach information for an area
 */
enum _:NavApproachInfo
{
    NAV_APPROACH_HERE_ID,
    NAV_APPROACH_HERE_AREA,
    NAV_APPROACH_PREV_ID,
    NAV_APPROACH_PREV_AREA,
    NavTraverseType:NAV_APPROACH_PREV_TO_HERE_HOW,
    NAV_APPROACH_NEXT_ID,
    NAV_APPROACH_NEXT_AREA,
    NavTraverseType:NAV_APPROACH_HERE_TO_NEXT_HOW
};

/**
 * NavArea - Navigable rectangular area (main structure)
 */
enum _:NavArea
{
    // Identification
    NAV_AREA_ID,
    NAV_AREA_PLACE,
    
    // Geometry (extent + center + corner heights)
    Float:NAV_AREA_EXTENT[NavExtent],
    Float:NAV_AREA_CENTER_X,
    Float:NAV_AREA_CENTER_Y,
    Float:NAV_AREA_CENTER_Z,
    Float:NAV_AREA_NE_Z,                // Northeast corner height
    Float:NAV_AREA_SW_Z,                // Southwest corner height
    
    // Attributes
    NavAttributeType:NAV_AREA_ATTRIBUTES,
    
    // Connections (4 directions)
    Array:NAV_AREA_CONNECT_NORTH,
    Array:NAV_AREA_CONNECT_EAST,
    Array:NAV_AREA_CONNECT_SOUTH,
    Array:NAV_AREA_CONNECT_WEST,
    
    // Approach areas
    Array:NAV_AREA_APPROACH,
    NAV_AREA_APPROACH_COUNT,
    
    // Pathfinding (A*)
    Float:NAV_AREA_TOTAL_COST,
    Float:NAV_AREA_COST_SO_FAR,
    NAV_AREA_PARENT,
    NavTraverseType:NAV_AREA_PARENT_HOW,
    NAV_AREA_MARKER,
    NAV_AREA_OPEN_MARKER,
    
    // Grid hash
    NAV_AREA_PREV_HASH,
    NAV_AREA_NEXT_HASH
};

/**
 * NavAreaGrid - Spatial grid for fast lookup
 */
enum _:NavAreaGrid
{
    NAV_GRID_SIZE_X,
    NAV_GRID_SIZE_Y,
    NAV_GRID_AREA_COUNT,
    Float:NAV_GRID_CELL_SIZE,
    Float:NAV_GRID_MIN_X,
    Float:NAV_GRID_MIN_Y,
    Array:NAV_GRID_CELLS,
    NAV_GRID_HASH_TABLE[256]
};

/**
 * NavLadder - Ladder or vertical connection
 */
enum _:NavLadder
{
    Float:NAV_LADDER_TOP_X,
    Float:NAV_LADDER_TOP_Y,
    Float:NAV_LADDER_TOP_Z,
    Float:NAV_LADDER_BOTTOM_X,
    Float:NAV_LADDER_BOTTOM_Y,
    Float:NAV_LADDER_BOTTOM_Z,
    Float:NAV_LADDER_LENGTH,
    NavDirType:NAV_LADDER_DIR,
    Float:NAV_LADDER_DIR_VEC_X,
    Float:NAV_LADDER_DIR_VEC_Y,
    NAV_LADDER_TOP_FORWARD_AREA,
    NAV_LADDER_TOP_LEFT_AREA,
    NAV_LADDER_TOP_RIGHT_AREA,
    NAV_LADDER_TOP_BEHIND_AREA,
    NAV_LADDER_BOTTOM_AREA,
    bool:NAV_LADDER_IS_DANGLING
};

/**
 * PathSegment - Segment of a path
 */
enum _:NavPathSegment
{
    NAV_PATH_AREA,
    NavTraverseType:NAV_PATH_HOW,
    Float:NAV_PATH_POS_X,
    Float:NAV_PATH_POS_Y,
    Float:NAV_PATH_POS_Z
};

/**
 * NavPath - Complete path
 */
enum _:NavPath
{
    Array:NAV_PATH_SEGMENTS,
    NAV_PATH_SEGMENT_COUNT
};

/**
 * PlaceDirectory - Directory of place names
 */
enum _:NavPlaceDirectory
{
    Array:NAV_PLACE_NAMES,
    Array:NAV_PLACE_IDS,
    NAV_PLACE_COUNT
};

// ============================================================================
// Debug names (stock to avoid warnings if unused)
// ============================================================================

stock const g_szNavDirName[][] = { "NORTH", "EAST", "SOUTH", "WEST" };
stock const g_szNavTraverseName[][] = { "GO_NORTH", "GO_EAST", "GO_SOUTH", "GO_WEST", "GO_LADDER_UP", "GO_LADDER_DOWN", "GO_JUMP" };

// ============================================================================
// Binary read helper functions
// ============================================================================

/**
 * Reads a float from the binary file
 */
stock bool:FileReadFloat(iFile, &Float:fValue)
{
    return fread(iFile, fValue, BLOCK_FLOAT) == BLOCK_FLOAT;
}
