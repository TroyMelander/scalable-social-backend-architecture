/*
==============================================================================
Description: Abstracted DDL for a highly partitioned User Interaction Fact table.
Architecture: Implements a monthly sliding-window partition strategy to manage 
              high-frequency telemetry and social connection data. Enables 
              rapid archiving of stale data without heavy DELETE operations.
Author: Troy M. Melander
==============================================================================
*/

-- 1. Create the Partition Function
-- Defines the boundary points for the partitions (e.g., breaking data up by month)
IF NOT EXISTS (SELECT * FROM sys.partition_functions WHERE name = 'pf_InteractionLog_Monthly')
BEGIN
    CREATE PARTITION FUNCTION pf_InteractionLog_Monthly (DATETIME2)
    AS RANGE RIGHT FOR VALUES (
        '2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01',
        '2026-05-01', '2026-06-01', '2026-07-01', '2026-08-01'
    );
END
GO

-- 2. Create the Partition Scheme
-- Maps the partitions defined above to specific database filegroups
IF NOT EXISTS (SELECT * FROM sys.partition_schemes WHERE name = 'ps_InteractionLog_Monthly')
BEGIN
    CREATE PARTITION SCHEME ps_InteractionLog_Monthly
    AS PARTITION pf_InteractionLog_Monthly
    ALL TO ([PRIMARY]); -- In production, these would map to fast NVMe secondary filegroups
END
GO

-- 3. Create the Partitioned Fact Table
IF OBJECT_ID('Core.FactUserInteraction', 'U') IS NOT NULL
    DROP TABLE Core.FactUserInteraction;
GO

CREATE TABLE Core.FactUserInteraction (
    InteractionID       BIGINT IDENTITY(1,1) NOT NULL,
    SourceUserID        UNIQUEIDENTIFIER NOT NULL,
    TargetUserID        UNIQUEIDENTIFIER NULL,
    InteractionTypeID   SMALLINT NOT NULL,     -- e.g., 1=ProfileView, 2=ConnectionReq, 3=StatusPing
    EventDTS            DATETIME2 NOT NULL,    -- The Partition Key
    LocationLatitude    DECIMAL(9,6) NULL,
    LocationLongitude   DECIMAL(9,6) NULL,
    ClientDevicePlatform VARCHAR(50) NULL,
    
    -- To align a primary key with a partition scheme, the partition column (EventDTS) MUST be part of the PK
    CONSTRAINT PK_FactUserInteraction PRIMARY KEY CLUSTERED (EventDTS, InteractionID)
) ON ps_InteractionLog_Monthly(EventDTS);
GO

-- 4. Create Aligned Non-Clustered Indexes
-- Optimized for the most common API lookup: finding a user's recent activity
CREATE NONCLUSTERED INDEX IX_FactUserInteraction_SourceUser
ON Core.FactUserInteraction (SourceUserID, EventDTS DESC)
INCLUDE (InteractionTypeID, TargetUserID)
ON ps_InteractionLog_Monthly(EventDTS); -- Index is aligned to the same partition scheme
GO
