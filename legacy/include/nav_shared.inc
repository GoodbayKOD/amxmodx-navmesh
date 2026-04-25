#if defined _nav_shared_included
  #endinput
#endif
#define _nav_shared_included

#include <nav_shared_const>

stock ComputeHashKey(const iID)
{
	return (iID & 0xFF);
}

stock Float:Extent_SizeX(const Float:vExtent[2]) { return (vExtent[m_vExtent_Hi[0]] - vExtent[m_vExtent_Lo[0]]); }
stock Float:Extent_SizeY(const Float:vExtent[2]) { return (vExtent[m_vExtent_Hi[1]] - vExtent[m_vExtent_Lo[1]]); }
stock Float:Extent_SizeZ(const Float:vExtent[2]) { return (vExtent[m_vExtent_Hi[2]] - vExtent[m_vExtent_Lo[2]]); }
stock Float:Extent_Area(const Float:vExtent[2])  { return (Extent_SizeX(vExtent) * Extent_SizeY(vExtent)); }

// return true if 'pos' is inside of this extent
stock bool:Math_ExtentContains(const Float:vPoint[3], const sArea[NavArea])
{
    return (
        vPoint[0] >= sArea[m_vAreaExtent][m_vExtent_Lo][0] && vPoint[0] <= sArea[m_vAreaExtent][m_vExtent_Hi][0] &&
        vPoint[1] >= sArea[m_vAreaExtent][m_vExtent_Lo][1] && vPoint[1] <= sArea[m_vAreaExtent][m_vExtent_Hi][1] &&
        vPoint[2] >= sArea[m_vAreaExtent][m_vExtent_Lo][2] && vPoint[2] <= sArea[m_vAreaExtent][m_vExtent_Hi][2]
    );
}

stock bool:Math_IsOverlapping2D(const sArea1[NavArea], const sArea2[NavArea])
{
    return (sArea2[m_vAreaExtent][m_vExtent_Lo][0] < sArea1[m_vAreaExtent][m_vExtent_Hi][0] &&
            sArea2[m_vAreaExtent][m_vExtent_Hi][0] > sArea1[m_vAreaExtent][m_vExtent_Lo][0] &&
            sArea2[m_vAreaExtent][m_vExtent_Lo][1] < sArea1[m_vAreaExtent][m_vExtent_Hi][1] &&
            sArea2[m_vAreaExtent][m_vExtent_Hi][1] > sArea1[m_vAreaExtent][m_vExtent_Lo][1]);
}

stock GetAttributeName(const iAttribute)
{
    new szReturn[64], len;
    copy(szReturn, charsmax(szReturn), "NONE");

    if(iAttribute & NAV_CROUCH)
        len = copy(szReturn, charsmax(szReturn), "NAV_CROUCH");

    if(iAttribute & NAV_JUMP)
    {
        if(len)
            len += formatex(szReturn[len], charsmax(szReturn) - len, "/NAV_JUMP");
        else
            len = formatex(szReturn, charsmax(szReturn), "NAV_JUMP");
    }

    if(iAttribute & NAV_PRECISE)
    {
        if(len)
            len += formatex(szReturn[len], charsmax(szReturn) - len, "/NAV_PRECISE");
        else
            len = formatex(szReturn, charsmax(szReturn), "NAV_PRECISE");
    }

    if(iAttribute & NAV_NO_JUMP)
    {
        if(len)
            len += formatex(szReturn[len], charsmax(szReturn) - len, "/NAV_NO_JUMP");
        else
            len = formatex(szReturn, charsmax(szReturn), "NAV_NO_JUMP");
    }

    return szReturn;
}

stock bool:IsEntityWalkable(pEntity, iFlags) 
{
    static szClassName[32], bWalk;
    entity_get_string(pEntity, EV_SZ_classname, szClassName, charsmax(szClassName));

    // if we hit a door, assume its walkable because it will open when we touch it
    if(containi(szClassName, "door") != -1) 
    {
        bWalk = WALK_THRU_DOORS;
    } 
    else if(equal(szClassName, "func_breakable")) 
    {
        // if we hit a breakable object, assume its walkable because we will shoot it when we touch it
        if(entity_get_float(pEntity, EV_FL_takedamage) == DAMAGE_YES) 
            bWalk = WALK_THRU_BREAKABLES;
    }

    return bool:(iFlags & bWalk);
}