#if defined _navmesh_included
    #endinput
#endif
#define _navmesh_included

#include <nav/navmesh_const>
#include <nav/navmesh_stocks>

/**
 * Loads the navigation file for the current map
 * 
 * @param mapname       Map name (without extension)
 * @return              NavErrorType indicating the result
 */
native NavErrorType:Navmesh_Load(const mapname[]);

/**
 * Unloads the navigation system and frees memory
 */
native Navmesh_Unload();

/**
 * Checks whether the navigation system is active
 * 
 * @return              true if loaded, false otherwise
 */
native bool:Navmesh_IsLoaded();

/**
 * Gets the total number of loaded areas
 * 
 * @return              Number of areas
 */
native Navmesh_GetAreaCount();

/**
 * Gets the area nearest to a position
 * 
 * @param origin        Origin position
 * @param maxDist       Maximum search distance (0 = no limit)
 * @param beneathLimit  Height limit below (for drops)
 * @return              Area index or INVALID_NAV_AREA if not found
 */
native Navmesh_GetNearestArea(const Float:origin[3], Float:maxDist = 0.0, Float:beneathLimit = 120.0);

/**
 * Gets an area by its unique ID
 * 
 * @param areaID        Area ID
 * @return              Area index or INVALID_NAV_AREA if not found
 */
native Navmesh_GetAreaByID(areaID);

/**
 * Gets the unique ID of an area
 * 
 * @param areaIndex     Area index
 * @return              Area ID or 0 if the index is invalid
 */
native Navmesh_GetAreaID(areaIndex);

/**
 * Gets the center of an area
 * 
 * @param areaIndex     Area index
 * @param center        Vector where the center will be stored
 * @return              true if successful, false if the index is invalid
 */
native bool:Navmesh_GetAreaCenter(areaIndex, Float:center[3]);

/**
 * Gets the bounds (extent) of an area
 * 
 * @param areaIndex     Area index
 * @param mins          Minimum vector of the area
 * @param maxs          Maximum vector of the area
 * @return              true if successful, false if the index is invalid
 */
native bool:Navmesh_GetAreaExtent(areaIndex, Float:mins[3], Float:maxs[3]);

/**
 * Gets the attributes of an area
 * 
 * @param areaIndex     Area index
 * @return              NavAttributeType flags or 0 if invalid
 */
native NavAttributeType:Navmesh_GetAreaAttributes(areaIndex);

/**
 * Checks whether a point is inside an area
 * 
 * @param areaIndex     Area index
 * @param point         Point to check
 * @return              true if the point is within the area
 */
native bool:Navmesh_IsPointInArea(areaIndex, const Float:point[3]);

/**
 * Gets the number of connected areas in a direction
 * 
 * @param areaIndex     Area index
 * @param dir           Direction (NavDirType)
 * @return              Number of connections or 0 if invalid
 */
native Navmesh_GetAdjacentCount(areaIndex, NavDirType:dir);

/**
 * Gets a specific adjacent area
 * 
 * @param areaIndex     Area index
 * @param dir           Direction (NavDirType)
 * @param index         Connection index (0 to GetAdjacentCount-1)
 * @return              Adjacent area index or INVALID_NAV_AREA
 */
native Navmesh_GetAdjacentArea(areaIndex, NavDirType:dir, index);

/**
 * Checks whether two areas are connected
 * 
 * @param areaIndex1    Index of area 1
 * @param areaIndex2    Index of area 2
 * @param dir           Direction from area 1 to area 2
 * @return              true if connected
 */
native bool:Navmesh_IsConnected(areaIndex1, areaIndex2, NavDirType:dir);

/**
 * Computes a path between two areas using A*
 * 
 * @param startArea     Index of the start area
 * @param goalArea      Index of the goal area
 * @param pathOut       Array where the path will be stored (NavPathSegment)
 * @param routeType     Route type (fastest/safest)
 * @return              true if a path was found
 * 
 * @note The pathOut array must be created before calling this function
 */
native bool:Navmesh_BuildPathFromArea(startArea, goalArea, Array:pathOut, NavRouteType:routeType = NAV_ROUTE_FASTEST);

/**
 * Computes a path between two positions
 * 
 * @param start         Start position
 * @param goal          Goal position
 * @param pathOut       Array where the path will be stored (NavPathSegment)
 * @param routeType     Route type (fastest/safest)
 * @return              true if a path was found
 * 
 * @note The pathOut array must be created before calling this function
 */
native bool:Navmesh_BuildPath(const Float:start[3], const Float:goal[3], Array:pathOut, NavRouteType:routeType = NAV_ROUTE_FASTEST);

/**
 * Gets the length of a path
 * 
 * @param path          Path array
 * @return              Number of segments in the path
 */
native Navmesh_GetPathLength(Array:path);

/**
 * Gets a specific segment of a path
 * 
 * @param path          Path array
 * @param index         Segment index
 * @param pos           Vector where the position will be stored
 * @param how           Variable where the traversal type will be stored
 * @param areaIndex     Variable where the area index will be stored
 * @return              true if successful
 */
native bool:Navmesh_GetPathSegment(Array:path, index, Float:pos[3], &NavTraverseType:how, &areaIndex);

/**
 * Clears a path (empties the array)
 * 
 * @param path          Path array
 */
native Navmesh_ClearPath(Array:path);

/**
 * Gets the total walked distance of a path (sum of segment lengths)
 *
 * @param path          Path array
 * @return              Total length in units (0.0 if invalid)
 */
native Float:Navmesh_GetPathDistance(Array:path);

/**
 * Returns true if a position is within `epsilon` units of the path's endpoint
 *
 * @param path          Path array
 * @param pos           World position to test
 * @param epsilon       Distance tolerance (default 20.0 if <= 0)
 * @return              true if within range of endpoint
 */
native bool:Navmesh_IsAtEndOfPath(Array:path, const Float:pos[3], Float:epsilon = 20.0);

/**
 * Computes a point a given distance along the path. Clamped to start/end if
 * out of bounds.
 *
 * @param path          Path array
 * @param distAlong     Distance along the path in units
 * @param point         Output position
 * @return              true if successful
 */
native bool:Navmesh_GetPointAlongPath(Array:path, Float:distAlong, Float:point[3]);

/**
 * Returns the segment index closest to the given distance along the path
 * without overshooting. -1 if invalid.
 *
 * @param path          Path array
 * @param distAlong     Distance along the path in units
 * @return              Segment index or -1 on error
 */
native Navmesh_GetSegmentIndexAlongPath(Array:path, Float:distAlong);

/**
 * Computes the closest point on the path (between segments [startIdx..endIdx])
 * to the given world position.
 *
 * @param path          Path array
 * @param worldPos      Reference world position
 * @param startIdx      First segment index to consider (clamped >= 1)
 * @param endIdx        Last segment index to consider (clamped <= count-1)
 * @param close         Output closest point
 * @return              true if successful
 */
native bool:Navmesh_FindClosestPointOnPath(Array:path, const Float:worldPos[3], startIdx, endIdx, Float:close[3]);

/**
 * Builds the path between two areas and returns the actual travel distance
 * along it. Returns -1.0 if no path exists.
 *
 * @param startArea     Start area index
 * @param goalArea      Goal area index
 * @return              Path length or -1.0 if unreachable
 */
native Float:Navmesh_TravelDistance(startArea, goalArea);

/**
 * Optimizes a path by removing redundant intermediate nodes that are
 * unobstructed by line-of-sight (mirrors CNavPath::Optimize).
 * Ladder segments are preserved as anchors.
 *
 * @param path          Path array (modified in place)
 * @param ignoreEnt     Entity index to ignore in traces (0 for none)
 * @return              New segment count after optimization
 */
native Navmesh_OptimizePath(Array:path, ignoreEnt = 0);

/**
 * Builds an A* path from `start` to `goal` (or `goalArea`) and stores it in
 * `path`. Throttles per-entity repath frequency to spread CPU load across
 * frames (mirrors CCSBot::ComputePath).
 *
 * @param entity        Entity for which the path is being built (used as key
 *                      for the repath cooldown). Pass 0 to skip throttling.
 * @param start         Start world position
 * @param goalArea      Goal area index, or Invalid_Area to use `goal` only
 * @param goal          Goal world position (used if goalArea invalid)
 * @param path          Output path array (must be created beforehand)
 * @param route         Route type (NAV_ROUTE_FASTEST / NAV_ROUTE_SAFEST)
 * @param repathDelay   Base seconds between repaths (jittered ±20%). 0.5 default.
 * @return              true if a new path was built, false if throttled or failed
 */
native bool:Navmesh_ComputePath(entity, const Float:start[3], goalArea, const Float:goal[3], Array:path, NavRouteType:route = NAV_ROUTE_FASTEST, Float:repathDelay = 0.5);

/**
 * Advances `pathIndex` along `path` based on the bot's current position and
 * computes a look-ahead goal point (mirrors CCSBot::UpdatePathMovement +
 * FindPathPoint).
 *
 * @param path          Path array
 * @param pathIndex     Current path index, updated in place (forward only)
 * @param origin        Bot's current world position
 * @param goalOut       Output: where the bot should move toward (look-ahead)
 * @param aheadRange    How far ahead along the path to aim (default 300 u)
 * @param closeEpsilon  Distance to endpoint to consider path complete (default 20 u)
 * @param ignoreEntity  If > 0, traces from origin to the look-ahead and walks
 *                      back along the path until the point is visible (mirrors
 *                      CCSBot::FindPathPoint sight walkback). 0 = skip check.
 * @return              NavPathResult: NAV_PATH_FAILURE / PROGRESSING / END_OF_PATH
 */
native NavPathResult:Navmesh_UpdatePathMovement(Array:path, &pathIndex, const Float:origin[3], Float:goalOut[3], Float:aheadRange = 300.0, Float:closeEpsilon = 20.0, ignoreEntity = 0);

/**
 * Returns true if the bot should jump to traverse the segment at `pathIndex`.
 * Triggers on NAV_TRAVERSE_JUMP or NAV_ATTR_JUMP areas (when going up only).
 *
 * @param path          Path array
 * @param pathIndex     Index of the segment about to be traversed
 * @return              true if a jump should be issued
 */
native bool:Navmesh_ShouldJump(Array:path, pathIndex);

/**
 * Resets the per-entity repath cooldown so the next ComputePath call is
 * guaranteed to recompute. Call when the entity respawns / changes target.
 *
 * @param entity        Entity index
 */
native Navmesh_ResetRepathTimer(entity);

/**
 * Tests whether the entity's origin is (approximately) inside the given area.
 *
 * @param entity        Entity index
 * @param areaIndex     Area index to test
 * @return              true if the entity is inside the area
 */
native bool:Navmesh_Contains(entity, areaIndex);

/**
 * Gets the closest point within an area
 * 
 * @param areaIndex     Area index
 * @param pos           Reference position
 * @param close         Vector where the closest point will be stored
 * @return              true if successful
 */
native bool:Navmesh_GetClosestPointInArea(areaIndex, const Float:pos[3], Float:close[3]);

/**
 * Computes the squared distance between a point and an area
 * 
 * @param areaIndex     Area index
 * @param pos           Reference position
 * @return              Squared distance
 */
native Float:Navmesh_GetDistanceSquaredToArea(areaIndex, const Float:pos[3]);

/**
 * Gets a random area from the map
 * 
 * @return              Index of a random area
 */
native Navmesh_GetRandomArea();

/**
 * Gets a random position within an area
 * 
 * @param areaIndex     Area index
 * @param pos           Vector where the position will be stored
 * @return              true if successful
 */
native bool:Navmesh_GetRandomPositionInArea(areaIndex, Float:pos[3]);

// ============================================================================
// Additional area functions
// ============================================================================

/**
 * Gets the position of a corner of the area
 * 
 * @param areaIndex     Area index
 * @param corner        Corner type (NavCornerType)
 * @param pos           Vector where the position will be stored
 * @return              true if successful
 */
native bool:Navmesh_GetAreaCorner(areaIndex, NavCornerType:corner, Float:pos[3]);

/**
 * Gets the Z height of the area at a specific XY position
 * 
 * @param areaIndex     Area index
 * @param x             X coordinate
 * @param y             Y coordinate
 * @return              Z height at that position
 */
native Float:Navmesh_GetAreaZ(areaIndex, Float:x, Float:y);

/**
 * Checks whether an area overlaps a 2D position
 * 
 * @param areaIndex     Area index
 * @param pos           Position to check
 * @return              true if the position is within the area in 2D
 */
native bool:Navmesh_IsAreaOverlapping(areaIndex, const Float:pos[3]);

/**
 * Checks whether two areas overlap
 * 
 * @param areaIndex1    Index of the first area
 * @param areaIndex2    Index of the second area
 * @return              true if they overlap
 */
native bool:Navmesh_AreAreasOverlapping(areaIndex1, areaIndex2);

/**
 * Computes the portal between two adjacent areas
 * 
 * @param fromArea      Index of the source area
 * @param toArea        Index of the destination area
 * @param dir           Connection direction
 * @param center        Vector where the portal center will be stored
 * @param halfWidth     Variable where the half-width will be stored
 * @return              true if successful
 */
native bool:Navmesh_ComputePortal(fromArea, toArea, NavDirType:dir, Float:center[3], &Float:halfWidth);

/**
 * Computes the closest point within the portal between two areas
 * 
 * @param fromArea      Index of the source area
 * @param toArea        Index of the destination area
 * @param dir           Connection direction
 * @param fromPos       Reference position
 * @param closePos      Vector where the closest point will be stored
 * @return              true if successful
 */
native bool:Navmesh_ComputeClosestPointInPortal(fromArea, toArea, NavDirType:dir, const Float:fromPos[3], Float:closePos[3]);

/**
 * Gets the Place of an area
 * 
 * @param areaIndex     Area index
 * @return              Place ID or UNDEFINED_PLACE
 */
native Navmesh_GetAreaPlace(areaIndex);

/**
 * Gets the name of a Place by its ID
 * 
 * @param placeID       Place ID
 * @param name          Buffer where the name will be stored
 * @param maxlen        Maximum buffer size
 * @return              true if successful
 */
native bool:Navmesh_GetPlaceName(placeID, name[], maxlen);

/**
 * Gets the number of approach areas for an area
 * 
 * @param areaIndex     Area index
 * @return              Number of approach areas
 */
native Navmesh_GetApproachCount(areaIndex);

/**
 * Gets information about an approach area
 * 
 * @param areaIndex     Area index
 * @param approachIndex Approach index (0 to GetApproachCount-1)
 * @param hereArea      Variable where the approach area index will be stored
 * @param prevArea      Variable where the previous area index will be stored
 * @param nextArea      Variable where the next area index will be stored
 * @param prevHow       Variable where how to arrive from prev will be stored
 * @param nextHow       Variable where how to go to next will be stored
 * @return              true if successful
 */
native bool:Navmesh_GetApproachInfo(areaIndex, approachIndex, &hereArea, &prevArea, &nextArea, &NavTraverseType:prevHow, &NavTraverseType:nextHow);

// ============================================================================
// Ladder functions
// ============================================================================

/**
 * Gets the number of loaded ladders
 * 
 * @return              Number of ladders
 */
native Navmesh_GetLadderCount();

/**
 * Gets information about a ladder
 * 
 * @param ladderIndex   Ladder index
 * @param top           Vector where the top position will be stored
 * @param bottom        Vector where the bottom position will be stored
 * @param length        Variable where the length will be stored
 * @param dir           Variable where the direction will be stored
 * @return              true if successful
 */
native bool:Navmesh_GetLadderInfo(ladderIndex, Float:top[3], Float:bottom[3], &Float:length, &NavDirType:dir);

// ============================================================================
// Editing functions
// ============================================================================

/**
 * Creates a new navigation area
 * 
 * @param mins          Minimum corner of the area
 * @param maxs          Maximum corner of the area
 * @return              Index of the created area or INVALID_NAV_AREA on failure
 */
native Navmesh_CreateArea(const Float:mins[3], const Float:maxs[3]);

/**
 * Deletes a navigation area
 * 
 * @param areaIndex     Index of the area to delete
 * @return              true if successful
 */
native bool:Navmesh_DeleteArea(areaIndex);

/**
 * Sets the attributes of an area
 * 
 * @param areaIndex     Area index
 * @param attributes    New attributes (NavAttributeType flags)
 * @return              true if successful
 */
native bool:Navmesh_SetAreaAttributes(areaIndex, NavAttributeType:attributes);

/**
 * Connects two areas in a specific direction
 * 
 * @param fromArea      Index of the source area
 * @param toArea        Index of the destination area
 * @param dir           Connection direction
 * @return              true if successful
 */
native bool:Navmesh_ConnectAreas(fromArea, toArea, NavDirType:dir);

/**
 * Disconnects two areas in a specific direction
 * 
 * @param fromArea      Index of the source area
 * @param toArea        Index of the destination area
 * @param dir           Connection direction to remove
 * @return              true if successful
 */
native bool:Navmesh_DisconnectAreas(fromArea, toArea, NavDirType:dir);

/**
 * Sets the Z height of a corner of the area
 * 
 * @param areaIndex     Area index
 * @param corner        Corner to modify (NavCornerType)
 * @param z             New Z height
 * @return              true if successful
 */
native bool:Navmesh_SetCornerZ(areaIndex, NavCornerType:corner, Float:z);

/**
 * Modifies the extent of an area in a specific direction
 * Allows expanding or shrinking one side of the area
 * 
 * @param areaIndex     Area index
 * @param dir           Direction of the side to modify (NavDirType)
 *                      NORTH = north side (minimum Y)
 *                      SOUTH = south side (maximum Y)
 *                      EAST  = east side  (maximum X)
 *                      WEST  = west side  (minimum X)
 * @param amount        Amount to move (positive = expand, negative = shrink)
 * @return              true if successful, false if the area would become inverted
 */
native bool:Navmesh_SetAreaExtent(areaIndex, NavDirType:dir, Float:amount);

/**
 * Saves the current navmesh to a .nav file
 * 
 * @param mapname       Map name (without extension)
 * @return              true if successful
 */
native bool:Navmesh_Save(const mapname[]);

/**
 * Initializes an empty navmesh for editing
 * Useful when no .nav file exists for the map
 * 
 * @return              true if successful
 */
native bool:Navmesh_Init();

/**
 * Splits an area into two parts
 * 
 * @param areaIndex     Index of the area to split
 * @param splitDir      Split direction (NORTH/SOUTH = horizontal, EAST/WEST = vertical)
 * @param splitPos      Position where to split (X or Y coordinate depending on direction)
 * @return              Index of the newly created area, or INVALID_NAV_AREA on failure
 */
native Navmesh_SplitArea(areaIndex, NavDirType:splitDir, Float:splitPos);

/**
 * Merges two areas into one
 * The resulting area will have the combined extent of both
 * 
 * @param area1         Index of the first area (kept)
 * @param area2         Index of the second area (removed)
 * @return              Index of the merged area, or INVALID_NAV_AREA on failure
 */
native Navmesh_MergeAreas(area1, area2);

/**
 * Creates an intermediate area between two unconnected areas
 * Useful for creating navigation bridges
 * 
 * @param area1         Index of the first area
 * @param area2         Index of the second area
 * @return              Index of the created area, or INVALID_NAV_AREA on failure
 */
native Navmesh_SpliceAreas(area1, area2);
