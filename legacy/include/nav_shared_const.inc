#if defined _nav_shared_const_included
  #endinput
#endif
#define _nav_shared_const_included

#define Invalid_Area      -1

#define NAV_VERSION        5
#define NAV_MAGIC_NUMBER   0xFEEDFACE

// ie: "no place"
#define UNDEFINED_PLACE    0
#define ANY_PLACE          0xFFFF

// Walks
#define WALK_THRU_DOORS      0x01
#define WALK_THRU_BREAKABLES 0x02
#define WALK_THRU_EVERYTHING (WALK_THRU_DOORS | WALK_THRU_BREAKABLES)

// Bits
#define NAV_ACTIVE  (1<<0)
#define NAV_SYNC    (1<<1)

const Float:NAV_EXTENT_MAX          = 9999999999.9
const Float:NAV_EXTENT_MIN          = -9999999999.9

const Float:GENERATION_STEP_SIZE    = 25.0; // (30) was 20, but bots can't always fit
const Float:STEP_HEIGHT             = 18.0; // if delta Z is greater than this, we have to jump to get up
const Float:JUMP_HEIGHT             = 41.8; // if delta Z is less than this, we can jump up on it
const Float:JUMP_CROUCH_HEIGHT      = 58.0; // (48) if delta Z is less than or equal to this, we can jumpcrouch up on it
const Float:HALF_PLAYER_HEIGHT      = 36.0;

const NAV_NEXTAREA_INT      = 1

// idk
new const DirectionName[][18] = { "NONE", "NORTH", "EAST", "SOUTH", "WEST"};

// Errors in load file
enum _:NavErrorType
{
    NAV_OK,
    NAV_CANT_ACCESS_FILE,
    NAV_INVALID_FILE,
    NAV_BAD_FILE_VERSION,
    NAV_CORRUPT_DATA,
}

enum _:NavAttributeType
{
	NAV_CROUCH  = 0x01, // must crouch to use this node/area
	NAV_JUMP    = 0x02, // must jump to traverse this area
	NAV_PRECISE = 0x04, // do not adjust for obstacles, just move along area
	NAV_NO_JUMP = 0x08, // inhibit discontinuity jumping
}

enum _:NavDirType
{
    NORTH = 0,
    EAST,
    SOUTH,
    WEST,

    NUM_DIRECTIONS
}

// Defines possible ways to move from one area to another
enum _:NavTraverseType
{
	// NOTE: First 4 directions MUST match NavDirType
	GO_NORTH = 0,
	GO_EAST,
	GO_SOUTH,
	GO_WEST,
	GO_LADDER_UP,
	GO_LADDER_DOWN,
	GO_JUMP,

	NUM_TRAVERSE_TYPES
}

enum _:NavCornerType
{
	NORTH_WEST = 0,
	NORTH_EAST,
	SOUTH_EAST,
	SOUTH_WEST,

	NUM_CORNERS
}

enum _:NavRelativeDirType
{
	FORWARD = 0,
	RIGHT,
	BACKWARD,
	LEFT,
	UP,
	DOWN,

    NUM_RELATIVE_DIRECTIONS
}

enum _:Extent
{ 
    Float:m_vExtent_Lo[3], 
    Float:m_vExtent_Hi[3] 
}

enum _:NavConnect 
{ 
    m_pConnectID,
    m_iConnectArea 
}

enum _:ApproachInfo 
{
    m_iApproachInfo_Here[NavConnect], // the approach area
    m_iApproachInfo_Prev[NavConnect], // the area just before the approach area on the path
    m_iApproachInfo_Next[NavConnect], // the area just after the approach area on the path

    NavTraverseType:m_iApproachInfo_PrevToHereHow,
    NavTraverseType:m_iApproachInfo_HereToNextHow
}

enum _:NavArea 
{
    m_pAreaID,  
    m_pAreaMarker,                          // used to flag the area as visited
    m_iAreaMarkerOpen,                      // if this equals the current marker value, we are on the open list

    Float:m_vAreaExtent[Extent],            // extents of area in world coords (NOTE: lo[2] is not necessarily the minimum Z, but corresponds to Z at point (lo[0], lo[1]), etc
    Float:m_vAreaCenter[3],                 // centroid of area
    Float:m_fAreaCorner_NorthEast,
    Float:m_fAreaCorner_SouthWest,
    Float:m_fAreaDistanceTotal,             // the distance so far plus an estimate of the distance left
    Float:m_fAreaDistanceFar,               // distance travelled so far
    
    Array:m_aAreaSpot,                      // Array[SpotEncounter] // list of possible ways to move thru this area, and the spots to look at as we do
    Array:m_aAreaApproach,                  // Array[ApproachInfo]
    Array:m_aAreaConnect[NUM_DIRECTIONS],   // a list of adjacent areas for each direction
    Array:m_aAreaOverlapList,               // list of areas that overlap this area
    m_iAreaPrevHash,
    m_iAreaNextHash,
    m_iAreaNextOpen,                        // only valid if m_openMarker == m_masterMarker
    Array:m_aAreaPrevOpen, 
    Array:m_aAreaParent,                    // the area just prior to this on in the search path

    NavAttributeType:m_iAreaAttribute,      // set of attribute bit flags (see NavAttributeType)
    NavTraverseType:m_aAreaParentHow        // how we get from parent to us
}

enum _:NavAreaGrid 
{
    m_iGridSizeX,
    m_iGridSizeY,
    m_iGridAreaCount,

    Array:m_aGridHandler,
    m_iGridHashTable[255],

    Float:m_fGridCellSize,
    Float:m_fGridMinX,
    Float:m_fGridMinY
}

enum _:PathSegment 
{ 
    m_iPathSegmentArea, 
    m_iPathSegmentHow,   // NavTraverseType:
    Float:m_vPathSegmentPosition[3]
}

enum _:NavPath 
{ 
    Array:m_aNavPathSegments, 
    m_iNavPathSegmentCount 
}