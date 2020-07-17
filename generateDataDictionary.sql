	--===================================================================================================
    -- Author: David Foster  
    -- Date: 01/28/20
    -- Repo: https://github.com/stmental/generateDataDictionary
    --
    -- This TSQL script is meant to be invoked externally to generate a HTML data dictionary/schema of 
    -- all the tables in a SQL Server database.  
    --
    -- Example to run from powershell:
    -- sqlcmd -S falpvm-dfoster\sqlexpress -d AdventureWorks2016  -i generateDataDictionary.sql | findstr /v /c:"---" > wf.html
    -- 
    -- Optional sqlcmd command line parameters that can be set with -v var = "value"
    -- Note that if these are not defined on the command line, then 'scripting variable not defined' error messages will 
    -- appear, but can be ignored
    -- ==================================================================================================
    -- includeViews - true/false, defaults to false
    -- includeTableMenu - true/false, defaults to true 
    -- includeSchema - comma-delimited string of schema to include, defaults to all, surround with quotes if providing multiple schemas
    --     Example: -v includeViews = true -v includeTableMenu = false  -v includeSchema = "Person, Sales"
    -- ==================================================================================================
    --
    -- The uses the sqlcmd command line tool to invoke the generateDataDictionary.sql script (or whatever you've
    -- called this file).  The SQL Server and database to use are also supplied.  The output of that is 
    -- piped to the findstr tool to remove any lines that begin with "---", which the select statements in 
    -- this script print, but we don't want.  Finally the output is sent to the twf.html file.  The server
    -- username and password can also be specified on the command line if not using your current Windows login
    --
    -- The bootstrap CSS is included from a CDN for minimal styling.  Currently only data for tables is 
    -- included, no views.
	--===================================================================================================
    
    Set nocount on
    DECLARE @UseSchemas TABLE (schemaName varchar(max)) 

    -- The ':on error ignore' line ensures that sqlcmd.exe will not fail when referencing an undefined scripting variable. 
    -- Remove this if you want your script to work in SSMS in regular mode, too.
    -- This is a hack to allow for default variable values passed on the command line
    :on error ignore 
    DECLARE @useViews nvarchar(100) = N'$(includeViews)';
    if @useViews = N'$' + N'(includeViews)' set @useViews = N'false';
    DECLARE @useTableMenu nvarchar(100) = N'$(includeTableMenu)';
    if @useTableMenu= N'$' + N'(includeTableMenu)' set @useTableMenu = N'true';
    DECLARE @passedSchemas nvarchar(max) = N'$(includeSchema)';
    if @passedSchemas = N'$' + N'(includeSchema)' 
        -- include all schemas
        insert into @UseSchemas
        select name from sys.schemas
    else
    BEGIN
        -- parse passed string for schemas
        insert into @UseSchemas (schemaName) (SELECT RTRIM(LTRIM(value)) FROM STRING_SPLIT(@passedSchemas, ',') WHERE LTRIM(RTRIM(value)) <> '')
    END

	DECLARE @TableName nvarchar(35)
	DECLARE @TableSchema nvarchar(256)
    DECLARE @IsView bit
	DECLARE @TablesReferencingPK nvarchar(max)
	DECLARE @FKTableRef nvarchar(max)

    IF OBJECT_ID('tempdb..#TableList') IS NOT NULL
       DROP TABLE #TableList
    CREATE TABLE #TableList (
        SCHEMA_NAME sysname collate database_default NOT NULL,
        TABLE_NAME sysname collate database_default NOT NULL,
        IS_VIEW bit NOT NULL)


    if @useViews = 'true' 
        DECLARE Tbls CURSOR 
        FOR
            SELECT O.name ObjectName,
                S.name SchemaName,
                CAST(CASE WHEN O.type = 'V' then 1 else 0 end as bit)
            FROM Sys.Objects O INNER JOIN Sys.Schemas S
                ON O.schema_id = S.schema_id
                WHERE O.type = 'U' OR O.type = 'V'
                AND S.name in (select schemaName from @UseSchemas) 
                order by S.name, O.name 
    else
        DECLARE Tbls CURSOR 
        FOR
        select sys.tables.name, sys.schemas.name, 0 
        from sys.tables
        INNER JOIN sys.schemas 
                ON sys.tables.schema_id = sys.schemas.schema_id
        where sys.schemas.name in (select schemaName from @UseSchemas) 
        order by sys.schemas.name, sys.tables.name

	OPEN Tbls

	PRINT '<HTML><head>'
    print '<link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/3.4.1/css/bootstrap.min.css" integrity="sha384-HSMxcRTRxnN+Bdg0JdbxYKrThecOKuH5zCYotlSAcp1+c8xmyTe9GYg1l9a69psu" crossorigin="anonymous">'
    print '<style type="text/css">thead{background-color: cadetblue; color: white;}</style>'
    print '<style type="text/css">#table-menu{display: block} #toggle:checked ~ #table-menu{display: none}</style>'
	print '</head><body class="" style="display:grid;grid-template-columns: min-content minmax(800px, 80%);grid-template-areas: ''a b''; margin-left:20px;margin-top:20px;grid-column-gap:15px">'

    PRINT '<div style="grid-area: b">'
	print '<h1>Data Dictionary: ' + db_name() + '</h1>';
    PRINT '<p>Server: ' + @@SERVERNAME + '</p>'
	print '<p>Autogenerated from database metadata at '
	select GETDATE();
    print ' using code from <a href="https://github.com/stmental/generateDataDictionary">https://github.com/stmental/generateDataDictionary</a>'
	print '</p>'


	-- Find all the foreign keys and table relationships and store in #fkList
    IF OBJECT_ID('tempdb..#FKList') IS NOT NULL
       DROP TABLE #FKList
    CREATE TABLE #FKList (
		FK_NAME sysname collate database_default NOT NULL,
        FKSCHEMA_NAME sysname collate database_default NOT NULL,
        FKTABLE_NAME sysname collate database_default NOT NULL,
        FKCOLUMN_NAME sysname collate database_default NOT NULL,
        PKSCHEMA_NAME sysname collate database_default NOT NULL,
		PKTABLE_NAME sysname collate database_default NOT NULL,
        PKCOLUMN_NAME sysname collate database_default NOT NULL)

	INSERT INTO #FKList 
		SELECT  obj.name AS FK_NAME,
            sch1.name as [fk_schema_name],
			tab1.name AS [fk_table_name],
			col1.name AS [fk_column_name],
            sch2.name as [pk_schema_name],
			tab2.name AS [pk_referenced_table_name],
			col2.name AS [pk_referenced_column_name]
		FROM sys.foreign_key_columns fkc
		INNER JOIN sys.objects obj
			ON obj.object_id = fkc.constraint_object_id
		INNER JOIN sys.tables tab1
			ON tab1.object_id = fkc.parent_object_id
		INNER JOIN sys.schemas sch1
			ON tab1.schema_id = sch1.schema_id
		INNER JOIN sys.columns col1
			ON col1.column_id = parent_column_id AND col1.object_id = tab1.object_id
		INNER JOIN sys.tables tab2
			ON tab2.object_id = fkc.referenced_object_id
		INNER JOIN sys.schemas sch2
			ON tab2.schema_id = sch2.schema_id            
		INNER JOIN sys.columns col2
			ON col2.column_id = referenced_column_id AND col2.object_id = tab2.object_id

	FETCH NEXT FROM Tbls
	INTO @TableName, @TableSchema, @IsView

	WHILE @@FETCH_STATUS = 0
	BEGIN

    -- Filter out any tables that are 'user' tables, but generated by SQL tools, like dbo.sysdiagrams
    if not exists(select 1 from sys.extended_properties A
	WHERE A.major_id = OBJECT_ID(@TableSchema + '.' + @TableName)
	and name = 'microsoft_database_tools_support' and minor_id = 0)
    BEGIN

        INSERT INTO #TableList VALUES (@TableSchema, @TableName, @IsView)

        Print '<h2><a name="' + @TableSchema + '.' + @TableName + '">' + @TableSchema + '.' +  @TableName + '</a>'
        IF @IsView = 1
            PRINT '<b>(View)</b>'
        PRINT '</h2>'
        PRINT '<p>'
        --Get the Description of the table
        --Characters 1-250
        Select rtrim(ltrim(substring(cast(Value as varchar(1000)),1,250))) FROM 
        sys.extended_properties A
        WHERE A.major_id = OBJECT_ID(@TableSchema + '.' + @TableName)
        and name = 'MS_Description' and minor_id = 0

        --Characters 251-500
        Select ltrim(substring(cast(Value as varchar(1000)),251, 250)) FROM 
        sys.extended_properties A
        WHERE A.major_id = OBJECT_ID(@TableSchema + '.' + @TableName)
        and name = 'MS_Description' and minor_id = 0
        PRINT '</p>'

        PRINT '<table class="table table-striped table-hover table-condensed table-bordered" style="background-color:lavender; font-size: smaller">'
        PRINT '<thead>'
        PRINT '<tr>'
        --Set up the Column Headers for the Table
        PRINT '<th>Column Name</th>'
        PRINT '<th>Description</th>'
        PRINT '<th>In Primary Key</th>'
        PRINT '<th>Is Foreign Key</th>'
        PRINT '<th>DataType</th>'
        PRINT '<th>Length</th>'
        PRINT '<th>Precision</th>'
        PRINT '<th>Scale</th>'
        PRINT '<th>Nullable</th>'
        PRINT '<th>Computed</th>'
        PRINT '<th>Identity</th>'
        PRINT '<th>Default Value</th>'
        PRINT '<th>Parent Table Ref</th>'
        PRINT '<th>Foreign Key References</th>'
        PRINT '</tr>'
        PRINT '</thead>'
        PRINT '</tbody>'

        --Get the Table Data

        SELECT '</tr>',
        '<tr>',
        '<td><strong>' + CAST(clmns.name AS VARCHAR(35)) + '</strong></td>' ,
        '<td>' + substring(ISNULL(CAST(exprop.value AS VARCHAR(255)),''),1,250),
        substring(ISNULL(CAST(exprop.value AS VARCHAR(500)),''),251,250) + '</td>',
        '<td>' + CAST(ISNULL(idxcol.index_column_id, 0)AS VARCHAR(20)) + '</td>',
        '<td>' + CAST(ISNULL(
        (SELECT TOP 1 1
        FROM sys.foreign_key_columns AS fkclmn
        WHERE fkclmn.parent_column_id = clmns.column_id
        AND fkclmn.parent_object_id = clmns.object_id
        ), 0) AS VARCHAR(20)) + '</td>',
        '<td>' + CAST(udt.name AS CHAR(15)) + '</td>' ,
        '<td>' + CAST(CAST(CASE WHEN typ.name IN (N'nchar', N'nvarchar') AND clmns.max_length <> -1
        THEN clmns.max_length/2
        ELSE clmns.max_length END AS INT) AS VARCHAR(20)) + '</td>',
        '<td>' + CAST(CAST(clmns.precision AS INT) AS VARCHAR(20)) + '</td>',
        '<td>' + CAST(CAST(clmns.scale AS INT) AS VARCHAR(20)) + '</td>',
        '<td>' + CAST(clmns.is_nullable AS VARCHAR(20)) + '</td>' ,
        '<td>' + CAST(clmns.is_computed AS VARCHAR(20)) + '</td>' ,
        '<td>' + CAST(clmns.is_identity AS VARCHAR(20)) + '</td>' ,
        '<td>' + isnull(CAST(cnstr.definition AS VARCHAR(100)),'') + '</td>',
        '<td>' + '<a href="#' + ISNULL((SELECT CAST(PKSCHEMA_NAME as varchar) + '.' + CAST(PKTABLE_NAME as varchar) from #FKList where FKTABLE_NAME = @TableName and FKCOLUMN_NAME = clmns.name), '') + '">'  
        +  ISNULL((SELECT CAST(PKSCHEMA_NAME as varchar) + '.' + CAST(PKTABLE_NAME as varchar) + '.' + CAST(PKCOLUMN_NAME as varchar) 
        from #FKList where FKSCHEMA_NAME = @TableSchema and FKTABLE_NAME = @TableName and FKCOLUMN_NAME = clmns.name), '')
        + '</a></td>',
        '<td>' +  cast(RTRIM(ISNULL(
            replace(replace(
                STUFF(
                (SELECT ',  ' + 
                    '<a href="#' + CAST(PKSCHEMA_NAME as varchar) + '.' + CAST(FKTABLE_NAME as varchar) + '">' +
                    CAST(PKSCHEMA_NAME as varchar) + '.' +CAST(FKTABLE_NAME as varchar) + '.' + CAST(FKCOLUMN_NAME as varchar) 
                    + '</a>'
                    from #FKList where PKSCHEMA_NAME = @TableSchema and PKTABLE_NAME = @TableName and PKCOLUMN_NAME = clmns.name
                    FOR XML PATH(''))
                ,1, 1, ''),
            '&lt;', '<'), '&gt;', '>')
        , '')) as varchar(700))
        + '</td>',
        '</tr>'
        FROM (
            SELECT O.name ObjectName,
                S.name SchemaName,
                O.object_id,
                O.type
            FROM Sys.Objects O INNER JOIN Sys.Schemas S
                ON O.schema_id = S.schema_id
        ) AS tbl
        INNER JOIN sys.all_columns AS clmns
        ON clmns.object_id=tbl.object_id
        LEFT OUTER JOIN sys.indexes AS idx
        ON idx.object_id = clmns.object_id
        AND 1 =idx.is_primary_key
        LEFT OUTER JOIN sys.index_columns AS idxcol
        ON idxcol.index_id = idx.index_id
        AND idxcol.column_id = clmns.column_id
        AND idxcol.object_id = clmns.object_id
        AND 0 = idxcol.is_included_column
        LEFT OUTER JOIN sys.types AS udt
        ON udt.user_type_id = clmns.user_type_id
        LEFT OUTER JOIN sys.types AS typ
        ON typ.user_type_id = clmns.system_type_id
        AND typ.user_type_id = typ.system_type_id
        LEFT JOIN sys.default_constraints AS cnstr
        ON cnstr.object_id=clmns.default_object_id
        LEFT OUTER JOIN sys.extended_properties exprop
        ON exprop.major_id = clmns.object_id
        AND exprop.minor_id = clmns.column_id
        AND exprop.name = 'MS_Description'
        WHERE (tbl.ObjectName = @TableName 
        --and exprop.class = 1  --I don't want to include comments on indexes
        ) 
        ORDER BY clmns.column_id ASC



        PRINT '</tbody></table>'
    END

	FETCH NEXT FROM Tbls
	INTO @TableName, @TableSchema, @IsView
	END

    PRINT '</div>'
    if @useTableMenu = 'true'
    BEGIN
        PRINT '<div style="grid-area:a; border: 1px black solid; padding: 10px" >'
        PRINT '<label for="toggle"><h3>Menu</h3></label>'
        PRINT '<input type="checkbox" id="toggle" style="opacity: 0">'
            PRINT '<div id="table-menu">'
            --PRINT '<h3>Tables</h3>'
            SELECT '<div>'+ 
            '<a style="margin-right: 10px" href="#' + SCHEMA_NAME + '.' + TABLE_NAME + '">' + SCHEMA_NAME + '.' + TABLE_NAME + '</a>' + 
            CAST(CASE WHEN IS_VIEW = 1 then '<b>(V)</b>' else '&nbsp;' end as varchar) +
                 '</div>' 
                from #TableList
            PRINT '</div>'
        PRINT '</div>'
    END
	PRINT '</body></HTML>'

	CLOSE Tbls
	DEALLOCATE Tbls