/*
==============================================================================
Description: Abstracted spatial query to return active users within a 
             specified geographic radius. 
Architecture: Utilizes MS SQL Server 'geography' data type and STDistance() 
              for high-performance proximity calculations. Assumes underlying 
              spatial indexes are applied to the UserLocation table.
Author: Troy M. Melander
==============================================================================
*/

CREATE OR ALTER PROCEDURE spatial.usp_GetUsersInRadius
    @SourceUserID UNIQUEIDENTIFIER,
    @SearchRadiusMiles INT = 25,
    @MaxResults INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    -- Constants for spatial conversion
    DECLARE @MetersPerMile FLOAT = 1609.34;
    DECLARE @SearchRadiusMeters FLOAT = @SearchRadiusMiles * @MetersPerMile;

    -- Variable to hold the source user's current coordinates
    DECLARE @SourceLocation GEOGRAPHY;

    BEGIN TRY
        -- 1. Retrieve the source user's validated location
        SELECT @SourceLocation = GeoLocation
        FROM Core.UserLocation
        WHERE UserID = @SourceUserID
          AND IsActive = 1;

        IF @SourceLocation IS NULL
        BEGIN
            -- Exit gracefully if user location is not found or inactive
            RETURN;
        END

        -- 2. Execute the proximity search using spatial indexing
        -- The query engine will leverage the spatial index on GeoLocation 
        -- before calculating the exact STDistance, minimizing CPU load.
        SELECT TOP (@MaxResults)
            u.UserID,
            u.ProfileAlias,
            -- Calculate precise distance and convert back to miles for the API layer
            (@SourceLocation.STDistance(l.GeoLocation) / @MetersPerMile) AS DistanceInMiles,
            l.LastPingDTS
        FROM Core.UserProfile u
        INNER JOIN Core.UserLocation l ON u.UserID = l.UserID
        WHERE u.IsVisible = 1
          AND u.UserID <> @SourceUserID
          AND l.GeoLocation.STDistance(@SourceLocation) <= @SearchRadiusMeters
        ORDER BY 
            DistanceInMiles ASC;

    END TRY
    BEGIN CATCH
        -- Standardized error handling architecture
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        
        -- EXEC etl.usp_LogError 'usp_GetUsersInRadius', @ErrorMessage;
        RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
    END CATCH
END
GO

/*
==============================================================================
-- MOCK EXECUTION & TESTING
==============================================================================
DECLARE @TestUserID UNIQUEIDENTIFIER = NEWID();
-- Note: Assuming test user coordinates are anchored near 32.7157° N, 117.1611° W

EXEC spatial.usp_GetUsersInRadius 
    @SourceUserID = @TestUserID, 
    @SearchRadiusMiles = 15, 
    @MaxResults = 50;
*/
