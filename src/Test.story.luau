--!strict
-- Services
-- Packages
-- Modules
-- Types
-- Constants
-- Variables
-- References
-- Class
return function(frame: Frame)
	local isAlive = true

	task.spawn(function()
		local Module = require(".")
		local array = table.create(2500, 1)
		local runner = Module.newIteratorRunner(array, function(i, v): true?
			if not isAlive then
				return true
			end
			print(i, v)
			-- if i > 1000 then
			-- 	task.wait(1)
			-- end
			return
		end, 1)

		Module.runAsync(runner, function(isComplete: boolean)
			print("done", isComplete)
		end)
	end)

	return function()
		isAlive = false
	end
end
