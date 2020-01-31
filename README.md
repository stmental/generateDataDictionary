# generateDataDictionary

This TSQL script is meant to be invoked externally to generate a HTML data dictionary/schema of 
all the tables in a SQL Server database.  It was originally based off of the script from here: [https://gist.github.com/mwinckler/2577364](https://gist.github.com/mwinckler/2577364)
 
Example to run from powershell.  This assumes Windows Authorization to the DB server, otherwise pass credentials.  See [https://docs.microsoft.com/en-us/sql/tools/sqlcmd-utility](sqlcmd utility) for more info.
```
sqlcmd -S falpvm-dfoster\sqlexpress -d TaskDB -i generateDataDictionary.sql | findstr /v /c:"---" > twf.html
```
 
Optional sqlcmd command line parameters that can be set with -v var = "value"
Note that if these are not defined on the command line, then 'scripting variable not defined' error messages will 
appear, but can be ignored
---
**includeViews** - true/false, defaults to false
**includeTableMenu** - true/false, defaults to true 
**includeSchema** - comma-delimited string of schema to include, defaults to all, surround with quotes if providing multiple schemas
     
Example
```
    -v includeViews = true -v includeTableMenu = false  -v includeSchema = "Purchasing,AssetManagement" 
```
---
 
 The uses the sqlcmd command line tool to invoke the generateDataDictionary.sql script (or whatever you've
 called this file).  The SQL Server and database to use are also supplied.  The output of that is 
 piped to the findstr tool to remove any lines that begin with "---", which the select statements in 
 this script print, but we don't want.  Finally the output is sent to the twf.html file.  The server
 username and password can also be specified on the command line if not using your current Windows login
 
 The bootstrap CSS is included from a CDN for minimal styling.  Currently only data for tables is 
 included, no views.