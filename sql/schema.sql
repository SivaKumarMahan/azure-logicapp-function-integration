-- Run once against the Azure SQL database (Query editor, sqlcmd, or Azure Data Studio).
-- Connect as the Microsoft Entra admin of the SQL server.

-- 1. Table used by the ProcessFile function.
IF OBJECT_ID(N'dbo.ProcessedFiles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.ProcessedFiles (
        Id            INT IDENTITY(1,1) PRIMARY KEY,
        FileName      NVARCHAR(255) NOT NULL,
        ProcessedTime DATETIME2(3)  NOT NULL CONSTRAINT DF_ProcessedFiles_ProcessedTime DEFAULT SYSUTCDATETIME(),
        Status        NVARCHAR(50)  NOT NULL,
        Content       NVARCHAR(MAX) NULL
    );
END;
GO

-- 2. Database user for the Function App's system-assigned managed identity.
--    Replace <function-app-name> with the Function App name (the identity has the same name).
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'<function-app-name>')
    CREATE USER [<function-app-name>] FROM EXTERNAL PROVIDER;
GO

-- 3. Least privilege: the function only inserts rows.
--    OUTPUT INSERTED.Id needs SELECT on that one column, so grant only the Id column.
GRANT INSERT ON dbo.ProcessedFiles TO [<function-app-name>];
GRANT SELECT (Id) ON dbo.ProcessedFiles TO [<function-app-name>];
GO
