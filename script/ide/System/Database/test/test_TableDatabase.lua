--[[
Title: Test Table database
Author(s): LiXizhi, 
Date: 2016/5/11
Desc: 
]]


function TestSQLOperations()
	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	-- this will start both db client and db server if not.
	local db = TableDatabase:new():connect("temp/mydatabase/", function() end);
	
	-- Note: `db.User` will automatically create the `User` collection table if not.
	-- clear all data
	db.User:makeEmpty({}, function(err, count) echo("deleted"..(count or 0)) end);
	-- this will automatically create `name` index
	db.User:findOne({name="this will create auto index"}, function(err, user) end)
	-- add record
	local user = db.User:new({name="LXZ", password="123"});
	user:save(function(err, data)  echo(data) end);
	-- implicit update record
	local user = db.User:new({name="LXZ", password="1", email="lixizhi@yeah.net"});
	user:save(function(err, data)  echo(data) end);
	-- insert another one
	db.User:insertOne({name="LXZ2", password="123", email="lixizhi@yeah.net"}, function(err, data)  echo(data) 	end)
	-- update one
	db.User:updateOne({name="LXZ2", password="2", email="lixizhi@yeah.net"}, function(err, data)  echo(data) end)
	-- force flush to disk, otherwise the db IO thread will do this at fixed interval
    db.User:flush({}, function(err, bFlushed) echo("flushed: "..tostring(bFlushed)) end);
	-- select one, this will automatically create `name` index
	db.User:findOne({name="LXZ"}, function(err, user) echo(user);	end)
	-- search on non-indexed rows
	db.User:find({password="2"}, function(err, rows) echo(rows); end);
	-- find all rows with custom timeout 1 second
	db.User:find({}, function(err, rows) echo(rows); end, 1000);
	-- remove item
	db.User:deleteOne({name="LXZ2"}, function(err, count) echo(count);	end);
	-- wait flush may take up to 3 seconds
	db.User:waitflush({}, function(err, data) echo({data, "data is flushed"}) end);
	-- find all rows
	db.User:find({}, function(err, rows) echo(rows); end);
	-- set cache to 2000KB, turn synchronous IO off, and use in-memory journal and 
	db.User:exec({CacheSize=-2000, IgnoreOSCrash=true, IgnoreAppCrash=true}, function(err, data) end);
	-- run sql command 
	db.User:exec("PRAGMA synchronous = ON", function(err, data) echo("mode changed") end);
	-- run select command from Collection 
	db.User:exec("Select * from Collection", function(err, rows) echo(rows) end);
end

function TestPerformance()
	NPL.load("(gl)script/ide/Debugger/NPLProfiler.lua");
	local npl_profiler = commonlib.gettable("commonlib.npl_profiler");
	npl_profiler.perf_reset();

	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	
	-- how many times for each CRUD operations.
	local nTimes = 10000;
	local insertFlush, testRoundTrip, randomCRUD, findMany;
	
	-- this will start both db client and db server if not.
	local db = TableDatabase:new():connect("temp/mydatabase/");

	-- uncomment to test aggressive mode
	-- db.User:exec({CacheSize=-2000, IgnoreOSCrash=true, IgnoreAppCrash=true}, function(err, data) end);

    db.PerfTest:makeEmpty({}, function() 
		echo("emptied");
		-- this will force creating index on `name`
		db.PerfTest:findOne({name = ""}, function() 
			db.PerfTest:flush({}, function()
				insertFlush();
			end);
		end);
    end);
    
	local lastTime = ParaGlobal.timeGetTime();
	local function CheckTickLog(...)
		if ((ParaGlobal.timeGetTime() - lastTime) > 1000) then
			LOG.std(nil, "info", ...);
			lastTime = ParaGlobal.timeGetTime();
		end
	end
	insertFlush = function()
		npl_profiler.perf_begin("insertFlush", true)
		local resultNum = 0;
		for count=1, nTimes do
			db.PerfTest:insertOne({count=count, data=math.random(), }, function(err, data)
				resultNum = resultNum +1;
				CheckTickLog("flushInsert", "%d %s", count, err);
				if(resultNum >= nTimes) then
					-- force flush
					db.PerfTest:flush({}, function()
						npl_profiler.perf_end("insertFlush", true)
						testRoundTrip();
					end)
				end
			end)
		end
	end
	
	local nRoundTimes = 100;
	local count = 0;
	-- latency: about 11ms
	testRoundTrip = function()
		if(count == 0) then
			npl_profiler.perf_begin("testRoundTrip", true)
		end
		if(count < nRoundTimes) then
			count = count + 1;
			
			db.PerfTest:insertOne({count=count, data=math.random(), }, function(err, data)
				CheckTickLog("roundtrip", "%d %s", count, err);
				testRoundTrip();
			end)
		else
			-- force flush
			db.PerfTest:flush({}, function()
				npl_profiler.perf_end("testRoundTrip", true)
				randomCRUD();
			end)
		end
	end

	-- randome CRUD operations
	randomCRUD = function()
		npl_profiler.perf_begin("randomCRUD", true)
		local resultNum = 0;
		local function next(err, data)
			resultNum = resultNum +1;
			CheckTickLog("randomCRUD", "%d %s", count, err);
			if(resultNum >= nTimes) then
				-- force flush
				db.PerfTest:flush({}, function()
					npl_profiler.perf_end("randomCRUD", true)
					findMany();
				end)
			end
		end
		for count=1, nTimes do
			local nCrudType = math.random(1, 4);
			if(nCrudType == 1) then
				db.PerfTest:findOne({count=math.random(1,nTimes)}, next);
			elseif(nCrudType == 2) then
				db.PerfTest:insertOne({count=nTimes+math.random(1,nTimes)}, next);
			elseif(nCrudType == 3) then
				db.PerfTest:deleteOne({count=math.random(1,nTimes)}, next);
			else
				db.PerfTest:updateOne({count=math.random(1,nTimes), data="updated"}, next);
			end
		end
	end

	findMany = function()
		npl_profiler.perf_begin("findMany", true)
		local resultNum = 0;
		for count=1, nTimes do
			db.PerfTest:findOne({count=math.random(1,nTimes)}, function(err, data)
				resultNum = resultNum +1;
				CheckTickLog("findMany", "%d %s", count, err);
				if(resultNum >= nTimes) then
					echo("finished.......")
					npl_profiler.perf_end("findMany", true)

					log(commonlib.serialize(npl_profiler.perf_get(), true));
				end
			end)
		end
	end

end

function TestTimeout()
	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	-- this will start both db client and db server if not.
	local db = TableDatabase:new():connect("temp/mydatabase/");
	
	db.User:silient({name="will always timeout"}, function(err, data) echo(err, data) end);
	db.User:silient({name="will always timeout"}, function(err, data) echo(err, data) end);
end


function TestBlockingAPI()
	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	-- this will start both db client and db server if not.
	local db = TableDatabase:new():connect("temp/mydatabase/");
	
	-- clear all data
	local err, data = db.User:makeEmpty({});

	-- add record
	local user = db.User:new({name="LXZ", password="123"});
	local err, data = user:save();   
	echo(data);
	
	-- implicit update record
	local user = db.User:new({name="LXZ", password="1", email="lixizhi@yeah.net"});
	local err, data = user:save();   
	echo(data);
end

function TestSqliteStore()
	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	NPL.load("(gl)script/ide/System/Database/SqliteStore.lua");
	local SqliteStore = commonlib.gettable("System.Database.SqliteStore");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	local db = TableDatabase:new():connect("temp/mydatabase/", function()  echo("connected1") end);
	local store = SqliteStore:new():init(db.User);

	-- testing adding record
	local user = db.User:new({name="LXZ", password="123"});
	user:save(function(err, data) echo(data) end);

	store:findOne({name="npl"}, function(err, data) echo(err, data) end);

	store:Close();
end

function TestConnect()
	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	local db1 = TableDatabase:new():connect("temp/mydatabase/", function()  echo("connected1") end);
	local db2 = TableDatabase:new():connect("temp/mydatabase/", function()  echo("connected2") end);
	db1.User:findOne({name="npl"}, function(err, data) echo(data) end);
	db2.User:findOne({name="npl"}, function(err, data) echo(data) end);
	db1.User:findOne({name="npl"}, function(err, data) echo(data) end);
end

function TestTable()
	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	-- this will start both db client and db server if not.
	local db = TableDatabase:new():connect("temp/mydatabase/", function()  echo("connected") end);
	local c1 = db("c1");
	local c2 = db.c2; 
	assert(c2.name == "c2");
	assert(db.c3.name == "c3");
	assert(db:GetCollectionCount() == 3);

	-- testing adding record
	local user = db.User:new({name="LXZ", password="123"});
	user:save(function(err, data)  echo(data) end);

	-- test select, automatically add index on `name`
	db.User:findOne({name="LXZ"}, function(err, user)
		assert(user.name == "LXZ" and user.password=="123");
	end)
end

function TestTableDatabase()
	NPL.load("(gl)script/ide/System/Database/TableDatabase.lua");
	local TableDatabase = commonlib.gettable("System.Database.TableDatabase");
	-- this will start both db client and db server if not.
	local db = TableDatabase:new():connect("temp/mydatabase/");
	-- this will automatically create the `User` collection table if not.
	local User = db.User; 
	-- another way to create/get User table.
	local User = db("User");

	-- select with automatic indexing
	-- Async Non-Blocking API (Recommended)
	User:findOne({name="LXZ"}, function(err, user)
		echo(user);
	end)
	-- Blocking API
	local user = User:findOne({name="LXZ"});

	-- insert/update 
	local user = User:new({name="LXZ", password="123"});
	-- Async save
	user:save(function()  end);
	-- Blocking API
	user:save();

	User:updateOne({name="LXZ"}, {password="312"}, function(err)	end);
end