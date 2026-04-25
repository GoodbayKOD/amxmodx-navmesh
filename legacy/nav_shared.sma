#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>
#include <reapi>
#include <xs>
#include <nav_shared>

#define nullptr         0
#define TASK_EDITOR     83242894

// Macros
#define NumEnum(%1)             (%1 - %1:1)
#define ByteToKb(%1)            (%1 / 1024)
#define Entity_Instance(%1)     ((%1 == -1) ? 0 : %1)

// Area & Grid handlers
new Array:g_aNavArea;
new Array:g_aNavGrid;

// Area Macros
#define Area_Count()            (ArraySize(g_aNavArea))
#define IsAreaValid(%1)         (0 > %1 > Area_Count())
#define IsAreaHandleValid()     (g_aNavArea != Invalid_Array)

// Grid Macros
#define IsGridValid()           (g_aNavGrid != Invalid_Array)

// Bit flags
new g_bNavs;

// Pointers
new g_pNavAreaNextID;

// Strings
new g_szMapName[32];

// Vectors
new Float:g_vExtent[Extent];
new g_msgSync;
new g_hTrace;

// cVars
new g_vDebugMode, g_vMaxIterFrame;

// Edit
new g_pEditor, g_iMarkedArea;

/*================================================================================
 [Plugin Data]
=================================================================================*/

public plugin_init()
{
    // Based in navmesh from ReGameDLL and navsystem from Hedgehog Fog 
    register_plugin("ReNavmesh", "1.0", "Goodbay");

    get_mapname(g_szMapName, charsmax(g_szMapName));
    strtolower(g_szMapName);

    if(load_navigation_map(g_szMapName) == NAV_OK)
    {
        log_amx("Navigation Map Loaded !");
        g_bNavs |= NAV_ACTIVE;
    }

    if(!(g_bNavs & NAV_ACTIVE))
        return;
    
    register_clcmd("nav_hud", "clcmd_edit_mode");

    bind_pcvar_num(create_cvar("nav_debug", "0", FCVAR_NONE, "Enable/Disable debug mode", .has_min = true, .has_max = true, .max_val = 1.0), g_vDebugMode);
    bind_pcvar_num(create_cvar("nav_max_iter_frame", "100", FCVAR_NONE, "Maximun of iter frames", .has_min = true, .min_val = 50.0, .has_max = true, .max_val = 100.0), g_vMaxIterFrame);

    g_msgSync = CreateHudSyncObj();
    g_hTrace = create_tr2();

    set_task(0.1, "Task_EditNavArea", .flags = "b");
}

public plugin_end()
{
    if(g_hTrace)
        free_tr2(g_hTrace);

    if(g_aNavArea != Invalid_Array) 
    {
        new sGrid[NavAreaGrid], i;
        ArrayGetArray(g_aNavArea, nullptr, sGrid);

        for(i = 0; i < ArraySize(sGrid[m_aGridHandler]); ++i) 
        {
            new Array:aAreas = ArrayGetCell(sGrid[m_aGridHandler], i);
            ArrayDestroy(aAreas);
        }

        ArrayDestroy(sGrid[m_aGridHandler]);
    }

    ArrayDestroy(g_aNavArea);
    ArrayDestroy(g_aNavGrid);
}

/*================================================================================
 [Client commands]
=================================================================================*/

public clcmd_edit_mode(const pPlayer)
{
    if(!is_user_connected(pPlayer))
        return;

    g_pEditor = (g_pEditor ? nullptr : pPlayer);
}

public Task_EditNavArea()
{
    if(!g_pEditor)
        return;

    // Not connected
    if(!is_user_connected(g_pEditor))
    {
        g_pEditor = nullptr;
        return;
    }

    static Float:vCursor[3], iArea, szMessage[512], len;
    Math_GetAimOrigin(g_pEditor, vCursor);

    // Start
    len = copy(szMessage, charsmax(szMessage), "Navmesh Area Info:^n");

    // Get nearest area
    if((iArea = Navmesh_GetNearestArea(vCursor, g_pEditor)) != Invalid_Area)
    {
        static sArea[NavArea], sConnection[NavConnect], i, j, iConnectionCount;
        ArrayGetArray(g_aNavArea, iArea, sArea);

        len += formatex(szMessage[len], charsmax(szMessage) - len, "- ID: [%d]^n- Attribute: [NONE]^n- North East Z [%.2f] - Sout West Z [%.2f]", 
        sArea[m_pAreaID], sArea[m_fAreaCorner_NorthEast], sArea[m_fAreaCorner_SouthWest]);

        // Iter in directions
        for(i = 0; i < NUM_DIRECTIONS; i++)
        {
            iConnectionCount = ArraySize(sArea[m_aAreaConnect][i]);
            len += formatex(szMessage[len], charsmax(szMessage) - len, "^n- Connections direction %s: [%d]", DirectionName[i], iConnectionCount);

            // Iter in connections
            for(j = 0; j < iConnectionCount; j++)
            {
                ArrayGetArray(sArea[m_aAreaConnect][i], j, sConnection); 
                len += formatex(szMessage[len], charsmax(szMessage) - len, "^n > Connected with Area: %d", sConnection[m_pConnectID]);
            }
        }
    }

    set_dhudmessage(255, 255, 255, 0.01, 0.20, 0, 0.0, 1.0, 0.1, 0.1);
    ShowSyncHudMsg(g_pEditor, g_msgSync, szMessage);
}

/*================================================================================
 [Loads]
=================================================================================*/

public load_navigation_map(const szMapName[])
{
    new szDirectory[127];
    format(szDirectory, charsmax(szDirectory), "maps/%s.nav", szMapName);

    if(!file_exists(szDirectory)) 
    {
        log_amx("File ^"%s^" not found!", szDirectory);
        return NAV_CANT_ACCESS_FILE;
    }

    // Init
    g_aNavArea = ArrayCreate(NavArea);
    g_aNavGrid = ArrayCreate(NavAreaGrid);
    g_pNavAreaNextID = NAV_NEXTAREA_INT;

    new iMagic, iVersion, i;
    new iFile = fopen(szDirectory, "rb");

    // Check magic number
    if(!FileReadInt32(iFile, iMagic) || iMagic != NAV_MAGIC_NUMBER) 
    {
        log_amx("Invalid or missing magic number in nav file");
        fclose(iFile);

        return NAV_INVALID_FILE;
    }

    // Read file version number
    if(!FileReadInt32(iFile, iVersion) || iVersion > NAV_VERSION) 
    {
        log_amx("Unsupported nav version %d (max %d)", iVersion, NAV_VERSION);
        fclose(iFile);

        return NAV_BAD_FILE_VERSION;
    }

    replace(szDirectory, charsmax(szDirectory), ".nav", ".bsp");

    if(iVersion >= 4)
        fseek(iFile, BLOCK_INT, SEEK_CUR);

    // Saltar directorio de lugares (places)
    if(iVersion >= NAV_VERSION) 
    {
        new iPlaceCount, iLen;
        FileReadUint16(iFile, iPlaceCount);

        for(i = 0; i < iPlaceCount; i++) 
        {
            // Reset
            iLen = nullptr;

            FileReadUint16(iFile, iLen);
            fseek(iFile, iLen, SEEK_CUR);
        }
    }

    // get number of areas
    new iAreaCount;
    FileReadInt32(iFile, iAreaCount);

    if(iAreaCount == nullptr)
        return NAV_INVALID_FILE;
        
    new vExtent[Extent], sArea[NavArea];
    vExtent[m_vExtent_Lo][0] = 9999999999.9;
    vExtent[m_vExtent_Lo][1] = 9999999999.9;

    vExtent[m_vExtent_Hi][0] = -9999999999.9;
    vExtent[m_vExtent_Hi][1] = -9999999999.9;

    // Load the areas and compute total extent
    for(i = 0; i < iAreaCount; i++) 
    { 
        Navmesh_AreaLoad(iFile, iVersion, bool:g_vDebugMode);
        ArrayGetArray(g_aNavArea, i, sArea);
        
        // Expand the bounding box of vExtent to sArea
        if(Float:sArea[m_vAreaExtent][m_vExtent_Lo][0] < vExtent[m_vExtent_Lo][0])
            vExtent[m_vExtent_Lo][0] = Float:sArea[m_vAreaExtent][m_vExtent_Lo][0];

        if(Float:sArea[m_vAreaExtent][m_vExtent_Lo][1] < vExtent[m_vExtent_Lo][1])
            vExtent[m_vExtent_Lo][1] = Float:sArea[m_vAreaExtent][m_vExtent_Lo][1];

        if(Float:sArea[m_vAreaExtent][m_vExtent_Hi][0] > vExtent[m_vExtent_Hi][0]) 
            vExtent[m_vExtent_Hi][0] = Float:sArea[m_vAreaExtent][m_vExtent_Hi][0];

        if(Float:sArea[m_vAreaExtent][m_vExtent_Hi][1] > vExtent[m_vExtent_Hi][1]) 
            vExtent[m_vExtent_Hi][1] = Float:sArea[m_vAreaExtent][m_vExtent_Hi][1];
    }

    // Finish using the file
    fclose(iFile);

    // Add the areas to the grid
    Navmesh_AreaGridInit(vExtent[m_vExtent_Lo][0], vExtent[m_vExtent_Hi][0], vExtent[m_vExtent_Lo][1], vExtent[m_vExtent_Hi][1]);

    for(i = 0; i < iAreaCount; i++) 
        Navmesh_GridAddArea(i);

    // Allow areas to connect to each other, etc
    for(i = 0; i < iAreaCount; i++) 
        Navmesh_AreaPostLoad(i);

    /* TODO: Load places & build ladders */

    // Some console information
    server_print(" ____________________________________");
    server_print("| Navmesh Shared - Build: N/D ");
    server_print("| Map name: %s - Map Size: %sKb", g_szMapName, add_point(ByteToKb(file_size(szDirectory))));
    server_print("| Nav version: %d", iVersion);
    server_print("| Found areas: %d", iAreaCount);
    server_print(" ‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾");
    return NAV_OK;
}

public Navmesh_AreaLoad(const iFile, const iVersion, const bool:bDebug)
{
    #pragma unused bDebug
    new sArea[NavArea], i, j;
    sArea[m_aAreaOverlapList] = ArrayCreate();
    sArea[m_aAreaApproach] = ArrayCreate(ApproachInfo);

    // Read Area ID (not same as Area Index)
    FileReadInt32(iFile, sArea[m_pAreaID]);

    if(sArea[m_pAreaID] >= g_pNavAreaNextID)
        g_pNavAreaNextID = sArea[m_pAreaID] + 1;

    // Flags & extent
    FileReadUint8(iFile, sArea[m_iAreaAttribute]);
    fread_blocks(iFile, sArea[m_vAreaExtent], 6, BLOCK_INT);

    // Center
    for(i = 0; i < 3; i++)
        sArea[m_vAreaCenter][i] = (sArea[m_vAreaExtent][m_vExtent_Lo][i] + sArea[m_vAreaExtent][m_vExtent_Hi][i]) / 2.0;

    // Corners height
    FileReadInt32(iFile, sArea[m_fAreaCorner_NorthEast]);
    FileReadInt32(iFile, sArea[m_fAreaCorner_SouthWest]);

    // Connections
    for(i = 0; i < NUM_DIRECTIONS; i++)
    {
        sArea[m_aAreaConnect][i] = ArrayCreate(NavConnect);

        new iConnectionCount, iConnect[NavConnect];
        FileReadInt32(iFile, iConnectionCount);

        for(j = 0; j < iConnectionCount; j++) 
        {
            FileReadInt32(iFile, iConnect[m_pConnectID]);
            ArrayPushArray(sArea[m_aAreaConnect][i], iConnect);
        }
    }

    // Hiding spots (skip)
    new iHidingSpotCount;
    FileReadUint8(iFile, iHidingSpotCount);
    fseek(iFile, iHidingSpotCount * ((iVersion == 1) ? (3 * BLOCK_INT) : (BLOCK_INT + (3 * BLOCK_INT) + BLOCK_CHAR)), SEEK_CUR);

    new iApproachCount;
    FileReadUint8(iFile, iApproachCount);

    for(i = 0; i < iApproachCount; i++) 
    {
        new iApproach[ApproachInfo];

        FileReadInt32(iFile, iApproach[m_iApproachInfo_Here][m_pConnectID]);
        FileReadInt32(iFile, iApproach[m_iApproachInfo_Prev][m_pConnectID]);

        FileReadUint8(iFile, iApproach[m_iApproachInfo_PrevToHereHow]);
        FileReadInt32(iFile, iApproach[m_iApproachInfo_Next][m_pConnectID]);
        FileReadUint8(iFile, iApproach[m_iApproachInfo_HereToNextHow]);

        ArrayPushArray(sArea[m_aAreaApproach], iApproach);
    }

    // Load and discart SpotEncounters
    Navmesh_Area_SpotLoad(iFile, iVersion);

    // Save changes
    ArrayPushArray(g_aNavArea, sArea);

    if(iVersion >= NAV_VERSION)
        fseek(iFile, BLOCK_SHORT, SEEK_CUR);
}

public Navmesh_AreaPostLoad(const iAreaIndex)
{
    new sArea[NavArea], sConnection[NavConnect], iArea, i, j;
    new Array:aAreaConnect;
    new iReturn = NAV_OK;

    ArrayGetArray(g_aNavArea, iAreaIndex, sArea);
    
    new iConnectionCount;
    for(i = 0; i < NUM_DIRECTIONS; i++)
    {
        if(!(iConnectionCount = ArraySize(sArea[m_aAreaConnect][i])))
            break;

        aAreaConnect = sArea[m_aAreaConnect][i];

        for(j = 0; j < iConnectionCount; j++)
        {
            ArrayGetArray(aAreaConnect, j, sConnection);
            iArea = Navmesh_GridGetAreaByID(sConnection[m_pConnectID]);
            ArraySetCell(aAreaConnect, j, iArea, m_iConnectArea);

            if(sConnection[m_pConnectID] && iArea == Invalid_Area)
            {
                log_amx("ERROR: Corrupt navigation data. Cannot connect Navigation Areas.^n");
                iReturn = NAV_CORRUPT_DATA;
            }
        }
    }

    new iApproachSize = ArraySize(sArea[m_aAreaApproach]);

    if(iApproachSize)
    {
        new const Approach_Name[][] = {"here", "prev", "next"};
        new sApproach[ApproachInfo], iApproachType, szMissing[24], len, iMember;
        ArrayGetArray(sArea[m_aAreaApproach], iAreaIndex, sApproach);

        for(i = 0; i < iApproachSize; i++)
        {
            ArrayGetArray(sArea[m_aAreaApproach], i, sApproach);

            for(j = 0; j < 3; j++)
            {
                iMember = ((m_iApproachInfo_Here + j) + m_pConnectID);
                iApproachType = sArea[iMember];
                sApproach[iMember] = Navmesh_GridGetAreaByID(iApproachType);

                if(iApproachType && sApproach[iMember] == Invalid_Area)
                    len += formatex(szMissing[len], charsmax(szMissing) - len, "%s%s", (j != 3) ? ", " : "", Approach_Name[j]);
            }

            ArraySetArray(sArea[m_aAreaApproach], i, sApproach);
        }

        // Error
        if(len)
        {
            log_amx("ERROR: Corrupt navigation data. Missing Approach Area (%s).^n", szMissing);
            iReturn = NAV_CORRUPT_DATA;
        }
    }
    
    // Aclaro q me papie los SpotEncounter (se me hacen irrelevantes)
    for(i = 0; i < Area_Count(); i++) 
    {
        if(iArea == i)
            continue;

        if(Area_IsOverlapping(iArea, i)) 
            ArrayPushCell(sArea[m_aAreaOverlapList], i);
    }

    return iReturn;
}

stock Navmesh_GridGetAreaByID(const pAreaID)
{
    // Las m_areaID empieza desde 1
    if(pAreaID <= nullptr)
        return Invalid_Area;

    new sArea[NavArea];
    new sGrid[NavAreaGrid];
    new iKey, iArea;

    ArrayGetArray(g_aNavGrid, nullptr, sGrid);
    iKey    = ComputeHashKey(pAreaID);
    iArea   = sGrid[m_iGridHashTable][iKey];

    while(iArea != Invalid_Area)
    {
        ArrayGetArray(g_aNavArea, iArea, sArea);

        if(sArea[m_pAreaID] == pAreaID)
            return iArea;

        iArea = sArea[m_iAreaNextHash];
    }

    return Invalid_Area;
}
stock Navmesh_AreaGet(const iAreaIndex, const iKey)
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavArea, iAreaIndex, sArea);

    return sArea[iKey];
}

// Add area to the grid
public Navmesh_GridAddArea(const iAreaIndex)
{
    new sArea[NavArea], sGrid[NavAreaGrid];

    // Get structures
    ArrayGetArray(g_aNavArea, iAreaIndex, sArea);
    ArrayGetArray(g_aNavGrid, nullptr, sGrid);

    // Lo Extent
    new iLoX = Math_WorldToGridX(sArea[m_vExtent_Lo][0]);
    new iLoY = Math_WorldToGridY(sArea[m_vExtent_Lo][1]);

    // Hi Extent
    new iHiX = Math_WorldToGridX(sArea[m_vExtent_Hi][0]);
    new iHiY = Math_WorldToGridY(sArea[m_vExtent_Hi][1]);

    new x, y;

    // Insert cells of grid
    for(y = iLoY; y <= iHiY; y++)
    {
        for(x = iLoX; x <= iHiX; x++)
        {
            new Array:aAreas = ArrayGetCell(sGrid[m_aGridHandler], x + y * sGrid[m_iGridSizeX]);
            ArrayPushCell(aAreas, iAreaIndex);
        }
    }

    // (ID & 0xFF)
    new iKey    = ComputeHashKey(sArea[m_pAreaID]);
    new iHead   = sGrid[m_iGridHashTable][iKey];

    // Initialize
    sArea[m_iAreaPrevHash] = Invalid_Area;
    sArea[m_iAreaNextHash] = iHead;

    if(iHead != Invalid_Area)
    {
        new sHeadArea[NavArea];
        ArrayGetArray(g_aNavArea, iHead, sHeadArea);
        sHeadArea[m_iAreaPrevHash] = iAreaIndex;
        ArraySetArray(g_aNavArea, iHead, sHeadArea);
    }

    sGrid[m_iGridHashTable][iKey] = iAreaIndex;
    sGrid[m_iGridAreaCount]++;

    // Update
    ArraySetArray(g_aNavGrid, nullptr, sGrid);
    ArraySetArray(g_aNavArea, iAreaIndex, sArea);
}

stock Navmesh_AreaGridInit(const Float:fMinX, const Float:fMaxX, const Float:fMinY, const Float:fMaxY) 
{
    new sGrid[NavAreaGrid], iGridSize, i;

    // Tamaño de celda fijo
    sGrid[m_fGridCellSize] = 300.0;

    // Mínimos
    sGrid[m_fGridMinX] = fMinX;
    sGrid[m_fGridMinY] = fMinY;

    // Tamaño del grid (corregido: +1 va fuera del paréntesis)
    sGrid[m_iGridSizeX] = floatround((fMaxX - fMinX) / sGrid[m_fGridCellSize] + 1);
    sGrid[m_iGridSizeY] = floatround((fMaxY - fMinY) / sGrid[m_fGridCellSize] + 1);

    // Contador inicial
    sGrid[m_iGridAreaCount] = 0;

    server_print("sGrid[m_iGridSizeX] = %d | sGrid[m_iGridSizeY] = %d", sGrid[m_iGridSizeX], sGrid[m_iGridSizeY]);

    // Crear contenedor para las celdas
    iGridSize = sGrid[m_iGridSizeX] * sGrid[m_iGridSizeY];
    sGrid[m_aGridHandler] = ArrayCreate(_, iGridSize);

    for (i = 0; i < iGridSize; ++i)
    {
        ArrayPushCell(sGrid[m_aGridHandler], ArrayCreate());
    }

    // Guardar en global
    if (ArrayFindValue(g_aNavGrid, nullptr) == -1)
        ArrayPushArray(g_aNavGrid, sGrid);
    else
        ArraySetArray(g_aNavGrid, nullptr, sGrid);
}

stock Navmesh_Area_SpotLoad(const iFile, const iVersion)
{
    new i, j;
    new iEncounterCount, iDummy, iDummyVector[3];
    FileReadInt32(iFile, iEncounterCount);

    for(i = 0; i < iEncounterCount; i++) 
    {
        FileReadInt32(iFile, iDummy); // rgEncounter[SpotEncounter_From][m_pConnectID]

        if(iVersion < 3) 
        {
            FileReadInt32(iFile, iDummy); // To
            fread_blocks(iFile, iDummyVector, 3, BLOCK_INT); // Path.From
            fread_blocks(iFile, iDummyVector, 3, BLOCK_INT); // Path.To
        } 
        else 
        {
            FileReadUint8(iFile, iDummy);  // FromDir
            FileReadInt32(iFile, iDummy);   // To
            FileReadUint8(iFile, iDummy);  // ToDir
        }

        // Leer y saltar lista de spots
        new iSpotCount;
        FileReadUint8(iFile, iSpotCount);

        if(iVersion < 3) 
        {
            for(j = 0; j < iSpotCount; j++) 
            {
                fread_blocks(iFile, iDummyVector, 3, BLOCK_INT);
                FileReadInt32(iFile, iDummy); // probablemente basura antigua
            } 
        } 
        else 
        {
            for(j = 0; j < iSpotCount; j++) 
            {
                FileReadInt32(iFile, iDummy);
                FileReadUint8(iFile, iDummy);
            }
        }
    }
}

stock Navmesh_GetNearestArea(const Float:vPosition[3], pIgnoreEnt, bool:bAnyZ = false) 
{
    if(g_aNavGrid == Invalid_Array)
        return Invalid_Area;

    new sGrid[NavAreaGrid], iCloseArea;
    ArrayGetArray(g_aNavGrid, nullptr, sGrid);
    new Float:fCloseDistance = 100000000.0;

    // Quick check
    if((iCloseArea = Navmesh_GridGetArea(vPosition, 120.0)) != Invalid_Area)
        return iCloseArea;

    // ensure source position is well behaved
    static Float:vSource[3];
    vSource = vPosition;

    if(!Math_GroundHeight(vPosition, vSource[2], pIgnoreEnt)) 
        return Invalid_Area;

    // Half player height
    vSource[2] += HALF_PLAYER_HEIGHT;

    new i;
    static Float:vAreaPos[3];
    static Float:vEnd[3];
    static Float:fFraction;

    // find closest nav area
    for(i = 0; i < Area_Count(); ++i) 
    {
        Math_GetClosestPointOnArea(i, vSource, vAreaPos);

        new Float:fDistance = floatpower(xs_vec_distance(vAreaPos, vSource), 2.0);

        // keep the closest area
        if (fDistance < fCloseDistance) 
        {
            // check LOS to area
            if(!bAnyZ) 
            {
                xs_vec_copy(vAreaPos, vEnd);
                vEnd[2] += HALF_PLAYER_HEIGHT;

                engfunc(EngFunc_TraceLine, vSource, vEnd, IGNORE_MONSTERS | IGNORE_GLASS, pIgnoreEnt, g_hTrace);
                get_tr2(g_hTrace, TR_flFraction, fFraction);

                if(fFraction != 1.0)
                    continue;
            }

            fCloseDistance = fDistance;
            iCloseArea = i;
        }
    }

    return iCloseArea;
}

stock Math_GetClosestPointOnArea(const iArea, const Float:vPosition[3], Float:vClosest[3])
{
	new sArea[NavArea];
	ArrayGetArray(g_aNavArea, iArea, sArea);

	if(vPosition[0] < sArea[m_vAreaExtent][m_vExtent_Lo][0])
	{
		if(vPosition[1] < sArea[m_vAreaExtent][m_vExtent_Lo][1])
		{
			// posición al noroeste
			xs_vec_copy(sArea[m_vAreaExtent][m_vExtent_Lo], vClosest);
		}
		else if(vPosition[1] > sArea[m_vAreaExtent][m_vExtent_Hi][1])
		{
			// posición al sudoeste
			vClosest[0] = sArea[m_vAreaExtent][m_vExtent_Lo][0];
			vClosest[1] = sArea[m_vAreaExtent][m_vExtent_Hi][1];
		}
		else
		{
			// posición al oeste
			vClosest[0] = sArea[m_vAreaExtent][m_vExtent_Lo][0];
			vClosest[1] = vPosition[1];
		}
	}
	else if(vPosition[0] > sArea[m_vAreaExtent][m_vExtent_Hi][0])
	{
		if(vPosition[1] < sArea[m_vAreaExtent][m_vExtent_Lo][1])
		{
			// posición al noreste
			vClosest[0] = sArea[m_vAreaExtent][m_vExtent_Hi][0];
			vClosest[1] = sArea[m_vAreaExtent][m_vExtent_Lo][1];
		}
		else if(vPosition[1] > sArea[m_vAreaExtent][m_vExtent_Hi][1])
		{
			// posición al sudeste
			xs_vec_copy(sArea[m_vAreaExtent][m_vExtent_Hi], vClosest);
		}
		else
		{
			// posición al este
			vClosest[0] = sArea[m_vAreaExtent][m_vExtent_Hi][0];
			vClosest[1] = vPosition[1];
		}
	}
	else if(vPosition[1] < sArea[m_vAreaExtent][m_vExtent_Lo][1])
	{
		// posición al norte
		vClosest[0] = vPosition[0];
		vClosest[1] = sArea[m_vAreaExtent][m_vExtent_Lo][1];
	}
	else if(vPosition[1] > sArea[m_vAreaExtent][m_vExtent_Hi][1])
	{
		// posición al sur
		vClosest[0] = vPosition[0];
		vClosest[1] = sArea[m_vAreaExtent][m_vExtent_Hi][1];
	}
	else
	{
		// dentro del área
		xs_vec_copy(vPosition, vClosest);
	}

	vClosest[2] = Math_AreaGetZ(iArea, vClosest);
}

// Given a position, return the nav area that IsOverlapping and is *immediately* beneath it
public Navmesh_GridGetArea(const Float:vPosition[3], Float:fBeneathLimit) 
{
    new sGrid[NavAreaGrid];

    if(!Navmesh_GetGrid(sGrid))
        return Invalid_Area;

    // search cell list to find correct area
    new iUseArea    = Invalid_Area;
    new Float:fUseZ = -99999999.9;

    static Float:vTestPosistion[3];
    vTestPosistion      = vPosition;
    vTestPosistion[2]   += 5.0;

    // get list in cell that contains position
    new Array:aList = ArrayGetCell(sGrid[m_aGridHandler], Math_WorldToGridX(vPosition[0]) + Math_WorldToGridY(vPosition[1]) * sGrid[m_iGridSizeX]);
    new i, Float:fAreaZ;

    for(i = 0; i < ArraySize(aList); i++) 
    {
        // check if position is within 2D boundaries of this area
        if(!Area_IsOverlappingPoint(i, vTestPosistion)) 
            continue;
        
        // project position onto area to get Z
        fAreaZ = Math_AreaGetZ(i, vTestPosistion);

        // if area is above us or is too far below us, skip it
        if(fAreaZ > vTestPosistion[2] || (fAreaZ < (vTestPosistion[2] - fBeneathLimit)))
            continue;

        // if area is higher than the one we have, use this instead
        if(fAreaZ > fUseZ) 
        {
            iUseArea = i;
            fUseZ = fAreaZ;
        }
    }

    return iUseArea;
}

stock bool:Area_IsOverlapping(const iArea1, const iArea2)
{
    new sArea1[NavArea], sArea2[NavArea];
    ArrayGetArray(g_aNavArea, iArea1, sArea1);
    ArrayGetArray(g_aNavArea, iArea2, sArea2);

    if(Math_IsOverlapping2D(sArea1, sArea2))
        return true;

    return false;
}

stock bool:Area_IsOverlappingPoint(const iArea, const Float:vPoint[3])
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavArea, iArea, sArea);

    return Math_ExtentContains(vPoint, sArea);
}

stock Float:Math_AreaGetZ(const iArea, const Float:vPosition[3])
{
    new sArea[NavArea];
    ArrayGetArray(g_aNavArea, iArea, sArea);

    new Float:fDivX         = sArea[m_vAreaExtent][m_vExtent_Hi][0] - sArea[m_vAreaExtent][m_vExtent_Lo][0];
    new Float:fDivY         = sArea[m_vAreaExtent][m_vExtent_Hi][1] - sArea[m_vAreaExtent][m_vExtent_Lo][1];
    new Float:fNorthEastZ   = sArea[m_fAreaCorner_NorthEast];

    // Prevenir división por 0 en áreas degeneradas
    if(fDivX == 0.0 || fDivY == 0.0)
        return fNorthEastZ;

    new Float:u             = floatclamp((vPosition[0] - sArea[m_vAreaExtent][m_vExtent_Lo][0]) / fDivX, 0.0, 1.0);
    new Float:fSouthWestZ   = sArea[m_fAreaCorner_SouthWest];
    new Float:fBaseZ        = sArea[m_vAreaExtent][m_vExtent_Lo][2];
    new Float:fNorthZ       = fBaseZ + u * (fNorthEastZ - fBaseZ);
    new Float:fSouthZ       = fSouthWestZ + u * (sArea[m_vAreaExtent][m_vExtent_Hi][2] - fSouthWestZ);

    return fNorthZ + (floatclamp((vPosition[1] - sArea[m_vAreaExtent][m_vExtent_Lo][1]) / fDivY, 0.0, 1.0)) * (fSouthZ - fNorthZ);
}

stock Math_WorldToGridX(const Float:fWorldX)
{
	new sGrid[NavAreaGrid], iVector;
	ArrayGetArray(g_aNavGrid, nullptr, sGrid);
	
	iVector = floatround((fWorldX - sGrid[m_fGridMinX]) / sGrid[m_fGridCellSize], floatround_ceil);
	return clamp(iVector, 0, sGrid[m_iGridSizeX] - 1);
}

stock Math_WorldToGridY(const Float:fWorldY)
{
	new sGrid[NavAreaGrid], iVector;
	ArrayGetArray(g_aNavGrid, nullptr, sGrid);

	iVector = floatround((fWorldY - sGrid[m_fGridMinY]) / sGrid[m_fGridCellSize], floatround_ceil);
	return clamp(iVector, 0, sGrid[m_iGridSizeX] - 1);
}

stock bool:Math_GroundHeight(const Float:vPosition[3], &Float:fHeight, pIgnoreEnt, Float:vOutput[3] = {0.0, 0.0, 0.0}) 
{
    // Vectors
    static Float:vFrom[3], Float:vTo[3], Float:vEnd[3];

    // Best cache
    static Float:vBest[3], Float:fBestHeight;
    vBest[0]    = vBest[1] = 0.00000;
    vBest[2]    = 1.0;
    fBestHeight = -99999.9;

    // Trace line
    static Float:fFraction, bool:bStartSolid, pHit;

    // Offsets
    static Float:fMaxOffset, Float:fOffset;
    fMaxOffset  = 100.0;
    fOffset     = 1.0;

    vTo[0] = vPosition[0];
    vTo[1] = vPosition[1];
    vTo[2] = vPosition[2] - 9999.9;

    static pIgnore;
    pIgnore = pIgnoreEnt;

    // Init as false (0)
    new bool:bFound;

    while(fOffset < fMaxOffset) 
    {
        vFrom[0] = vPosition[0];
        vFrom[1] = vPosition[1];
        vFrom[2] = vPosition[2] + fOffset;

        engfunc(EngFunc_TraceLine, vFrom, vTo, IGNORE_MONSTERS, pIgnore, g_hTrace);
        get_tr2(g_hTrace, TR_flFraction, fFraction);

        bStartSolid = bool:get_tr2(g_hTrace, TR_StartSolid);
        pHit        = Entity_Instance(get_tr2(g_hTrace, TR_pHit));

        // Touch something
        if(fFraction != 1.0 && pHit) 
        {
            if(IsEntityWalkable(pHit, WALK_THRU_DOORS | WALK_THRU_BREAKABLES)) 
            {
                pIgnore = pHit;
                continue;
            }
        }

        if(!bStartSolid) 
        {
            get_tr2(g_hTrace, TR_vecEndPos, vEnd);

            if(!bFound || vEnd[2] > fBestHeight) 
            {
                bFound = true;
                fBestHeight = vEnd[2];

                get_tr2(g_hTrace, TR_vecPlaneNormal, vBest);
            }

            break;
        }

        fOffset += 10.0;
    }

    if(!bFound) 
        return false;

    fHeight = fBestHeight;
    xs_vec_copy(vBest, vOutput);
    return true;
}

stock Math_GetAimOrigin(const pPlayer, Float:vOutput[3], const Float:fOffset = 0.0)
{
    // Punto de mira
    new Float:g_vOrigin[3], Float:g_vStart[3], Float:g_vEnd[3];
    new Float:g_vOffset[3], Float:g_vForward[3], Float:g_vPlane[3];
    entity_get_vector(pPlayer, EV_VEC_origin, g_vOrigin);
    entity_get_vector(pPlayer, EV_VEC_view_ofs, g_vPlane);

    xs_vec_add(g_vOrigin, g_vPlane, g_vStart);

    entity_get_vector(pPlayer, EV_VEC_v_angle, g_vPlane);
    angle_vector(g_vPlane, ANGLEVECTOR_FORWARD, g_vForward);

    // Pa adelante
    xs_vec_add_scaled(g_vStart, g_vForward, 9999.0, g_vEnd);

    // Trace
    engfunc(EngFunc_TraceLine, g_vStart, g_vEnd, DONT_IGNORE_MONSTERS, pPlayer, g_hTrace);
    get_tr2(g_hTrace, TR_vecEndPos, g_vEnd);

    // Add offset
    if(fOffset > 0)
    {
        get_tr2(g_hTrace, TR_vecPlaneNormal, g_vOffset);
        xs_vec_add_scaled(g_vEnd, g_vOffset, fOffset, g_vEnd);
    }

    vOutput = g_vEnd;
}

stock Navmesh_GetGrid(sOutput[NavAreaGrid])
{
    if(!IsGridValid())
        return false;

    ArrayGetArray(g_aNavGrid, nullptr, sOutput);
    return true;
}

stock Navmesh_GetArea(const iArea, sOutput[NavArea])
{
    if(!IsAreaValid(iArea) || !IsAreaHandleValid())
        return false;

    ArrayGetArray(g_aNavArea, nullptr, sOutput);
    return true;
}