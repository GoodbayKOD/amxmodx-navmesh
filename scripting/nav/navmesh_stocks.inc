/**
 * navmesh_stocks.inc
 * 
 * Helper functions (stocks) for the navigation system
 * 
 * @author Goodbay
 * @version 1.0
 */

#if defined _navmesh_stocks_included
    #endinput
#endif
#define _navmesh_stocks_included

// ============================================================================
// Direction utilities
// ============================================================================

/**
 * Gets the opposite direction
 * 
 * @param dir           Direction
 * @return              Opposite direction
 */
stock NavDirType:Navmesh_OppositeDirection(NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: return NAV_DIR_SOUTH;
        case NAV_DIR_EAST:  return NAV_DIR_WEST;
        case NAV_DIR_SOUTH: return NAV_DIR_NORTH;
        case NAV_DIR_WEST:  return NAV_DIR_EAST;
    }
    return NAV_DIR_NORTH;
}

/**
 * Gets the direction to the left
 * 
 * @param dir           Direction
 * @return              Direction to the left
 */
stock NavDirType:Navmesh_DirectionLeft(NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: return NAV_DIR_WEST;
        case NAV_DIR_EAST:  return NAV_DIR_NORTH;
        case NAV_DIR_SOUTH: return NAV_DIR_EAST;
        case NAV_DIR_WEST:  return NAV_DIR_SOUTH;
    }
    return NAV_DIR_NORTH;
}

/**
 * Gets the direction to the right
 * 
 * @param dir           Direction
 * @return              Direction to the right
 */
stock NavDirType:Navmesh_DirectionRight(NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: return NAV_DIR_EAST;
        case NAV_DIR_EAST:  return NAV_DIR_SOUTH;
        case NAV_DIR_SOUTH: return NAV_DIR_WEST;
        case NAV_DIR_WEST:  return NAV_DIR_NORTH;
    }
    return NAV_DIR_NORTH;
}

/**
 * Converts a direction to an angle
 * 
 * @param dir           Direction
 * @return              Angle in degrees
 */
stock Float:Navmesh_DirectionToAngle(NavDirType:dir)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: return 270.0;
        case NAV_DIR_EAST:  return 0.0;
        case NAV_DIR_SOUTH: return 90.0;
        case NAV_DIR_WEST:  return 180.0;
    }
    return 0.0;
}

/**
 * Converts an angle to a direction
 * 
 * @param angle         Angle in degrees
 * @return              Nearest direction
 */
stock NavDirType:Navmesh_AngleToDirection(Float:angle)
{
    while(angle < 0.0)
        angle += 360.0;
    
    while(angle > 360.0)
        angle -= 360.0;
    
    if(angle < 45.0 || angle > 315.0)
        return NAV_DIR_EAST;
    
    if(angle >= 45.0 && angle < 135.0)
        return NAV_DIR_SOUTH;
    
    if(angle >= 135.0 && angle < 225.0)
        return NAV_DIR_WEST;
    
    return NAV_DIR_NORTH;
}

/**
 * Adds a direction vector to a position
 * 
 * @param pos           Position to modify
 * @param dir           Direction
 * @param amount        Amount to add
 */
stock Navmesh_AddDirectionVector(Float:pos[3], NavDirType:dir, Float:amount)
{
    switch(dir)
    {
        case NAV_DIR_NORTH: pos[1] -= amount;
        case NAV_DIR_SOUTH: pos[1] += amount;
        case NAV_DIR_EAST:  pos[0] += amount;
        case NAV_DIR_WEST:  pos[0] -= amount;
    }
}

/**
 * Gets the unit vector for a direction
 * 
 * @param dir           Direction
 * @param vec           Vector where the result will be stored
 */
stock Navmesh_DirectionToVector(NavDirType:dir, Float:vec[2])
{
    switch(dir)
    {
        case NAV_DIR_NORTH: { vec[0] = 0.0; vec[1] = -1.0; }
        case NAV_DIR_SOUTH: { vec[0] = 0.0; vec[1] = 1.0; }
        case NAV_DIR_EAST:  { vec[0] = 1.0; vec[1] = 0.0; }
        case NAV_DIR_WEST:  { vec[0] = -1.0; vec[1] = 0.0; }
    }
}

/**
 * Computes the connection point between two adjacent areas
 * This is the point on the shared edge between both areas
 * 
 * @param iFromArea     Source area
 * @param iToArea       Destination area (must be adjacent)
 * @param vPoint        Vector where the connection point will be stored
 * @return              true if the connection was found, false if not adjacent
 */
stock bool:Navmesh_GetConnectionPoint(iFromArea, iToArea, Float:vPoint[3])
{
    new Float:vFromMins[3], Float:vFromMaxs[3];
    new Float:vToMins[3], Float:vToMaxs[3];
    
    if(!Navmesh_GetAreaExtent(iFromArea, vFromMins, vFromMaxs))
        return false;
    if(!Navmesh_GetAreaExtent(iToArea, vToMins, vToMaxs))
        return false;
    
    // Search for the direction in which the connection exists
    for(new NavDirType:dir = NAV_DIR_NORTH; dir < NUM_NAV_DIRECTIONS; dir++)
    {
        new iCount = Navmesh_GetAdjacentCount(iFromArea, dir);
        for(new i = 0; i < iCount; i++)
        {
            if(Navmesh_GetAdjacentArea(iFromArea, dir, i) == iToArea)
            {
                // Connection found, compute the point on the shared edge
                new Float:fOverlapMin, Float:fOverlapMax;
                
                switch(dir)
                {
                    case NAV_DIR_NORTH: // North edge (minimum Y of the from area)
                    {
                        // Overlap on X
                        fOverlapMin = floatmax(vFromMins[0], vToMins[0]);
                        fOverlapMax = floatmin(vFromMaxs[0], vToMaxs[0]);
                        vPoint[0] = (fOverlapMin + fOverlapMax) / 2.0;
                        vPoint[1] = vFromMins[1]; // North edge
                    }
                    case NAV_DIR_SOUTH: // South edge (maximum Y of the from area)
                    {
                        fOverlapMin = floatmax(vFromMins[0], vToMins[0]);
                        fOverlapMax = floatmin(vFromMaxs[0], vToMaxs[0]);
                        vPoint[0] = (fOverlapMin + fOverlapMax) / 2.0;
                        vPoint[1] = vFromMaxs[1]; // South edge
                    }
                    case NAV_DIR_EAST: // East edge (maximum X of the from area)
                    {
                        fOverlapMin = floatmax(vFromMins[1], vToMins[1]);
                        fOverlapMax = floatmin(vFromMaxs[1], vToMaxs[1]);
                        vPoint[0] = vFromMaxs[0]; // East edge
                        vPoint[1] = (fOverlapMin + fOverlapMax) / 2.0;
                    }
                    case NAV_DIR_WEST: // West edge (minimum X of the from area)
                    {
                        fOverlapMin = floatmax(vFromMins[1], vToMins[1]);
                        fOverlapMax = floatmin(vFromMaxs[1], vToMaxs[1]);
                        vPoint[0] = vFromMins[0]; // West edge
                        vPoint[1] = (fOverlapMin + fOverlapMax) / 2.0;
                    }
                }
                
                // Compute Z using the destination area
                vPoint[2] = Navmesh_GetAreaZ(iToArea, vPoint[0], vPoint[1]);
                return true;
            }
        }
    }
    
    return false;
}
