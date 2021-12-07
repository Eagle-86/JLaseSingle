--[[
JLase 0.1.4 Beta by Eagle86
Script code used: JtacAutoLase	https://github.com/ciribob/DCS-JTACAutoLaze          

RUS ----------------------------------------------------------------------------------------------------------------
Добавлено:
1. возможность выбирать группу для подсветки
2. возможность выбрать тип ПВО для подсветки
3. возможность выбрать тип статический для подсветки
4. Коалицию юнита jtac и противника указывать не нужно. Выбор делается исходя из коалиции юнита jtac
5. возможность остановить подсветку отдельного JTAC или всех JTAC:  StopJTAC(jtacGroupName) и StopAllJTAC() -- Возможны ошибки
6. таймер подсвета  
 
**Пример:**
 JLase('JTAC1', 1113, false , "all" , 2 , "all", 30)** 

Параметры:
1: Имя группы JTAC
2: Код лазера - например: 1688 (По умолчанию у самолетов НАТО), 1113 (Для модулей из серии Горячие скалы 3) 
3: Дымы включены или нет (true, false)
4: Тип: vehicle - техника,troop - живая сила, sam - пво, static - статические, armor - бронетехника, artillery - артилерия, build - укрепления, all-все
5: Цвет дыма: Green = 0, Red = 1, White = 2, Orange = 3, Blue = 4
6: Название группы или все (all)
7: Время подсвета в секундах или 0 - бесконечно
Примечание: Тип - all для статических объектов не работает. 
Чтобы подсвечивать все статические объекты используйте тип - static, а группу - all
-------------------------------------------------------------------------------------------------------------------
]]

-- Конфигурация/Config

SIDE_COALITION = 1 -- coalition / коалиция (1 - red, 2 - blue)

JTAC_maxDistance = 10000 -- lasing distance / дальность работы

JTAC_smokeOn = true -- smooke on / включает маркировку цели дымом, может быть переопределен

JTAC_smokeColour = 1 -- Color smooke / Цвет дыма            Green/Зеленый = 0 , Red/Красный= 1, White/Белый = 2, Orange/Оранжевый = 3, Blue/Синий = 4

JTAC_jtacStatusF10 = true -- Menu F10 / Меню F10 

JTAC_location = true -- Show "координаты " / Показывать координаты

JTAC_lock =  "all" -- "vehicle" OR "troop" OR "all" forces JTAC to only lock vehicles or troops or all ground units 

errorShow  = true -- show error / показывать ошибки

showTimeMin = 5			-- show text timer - 1/ время отображения сообщений - 1
showTimeMax = 20		-- show text timer - 2/ время отображения сообщений - 2
-------------------------------------------------------------------------------------------------------------------
GLOBAL_JTAC_LASE = {}
GLOBAL_JTAC_IR = {}
GLOBAL_JTAC_SMOKE = {}
GLOBAL_JTAC_UNITS = {} -- список подразделений  по команде F10 
GLOBAL_JTAC_CURRENT_TARGETS = {}
GLOBAL_JTAC_RADIO_ADDED = {} --keeps track of who's had the radio command added
GLOBAL_JTAC_LASER_CODES = {} -- keeps track of laser codes for jtac

GLOBAL_JTAC_TIMER = {}           -- таймер JTAC
GLOBAL_JTAC_TIMER_COUNT = {}
GLOBAL_JTAC_UNIT_VISIBLE = {} -- юниты в зоне



function JLase(jtacGroupName, laserCode,smoke,lock,colour, targetGroupName, timeLase)
	if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil then StopJTAC(jtacGroupName) end
	JLaseStart(jtacGroupName, laserCode,smoke,lock,colour, targetGroupName, timeLase)
end

function JLaseStart(jtacGroupName, laserCode,smoke,lock,colour, targetGroupName, timeLase)
local _time = timeLase or 0
	
    if smoke == nil then
    
        smoke = JTAC_smokeOn  
    end

    if lock == nil then
    
        lock = JTAC_lock
    end

    if colour == nil then
    	colour = JTAC_smokeColour
    end

    GLOBAL_JTAC_LASER_CODES[jtacGroupName] = laserCode

    
    local jtacGroup = getGroup(jtacGroupName)
    local jtacUnit



    if jtacGroup == nil or #jtacGroup == 0 then

        notify('Наш JTAC (ПАН) ' .. jtacGroupName .. ' уничтожен!', showTimeMax)

        --удалить из списка
        GLOBAL_JTAC_UNITS[jtacGroupName] = nil

        cleanupJTAC(jtacGroupName)
        return
    else

        jtacUnit = jtacGroup[1]
		SIDE_COALITION = jtacUnit:getCoalition()
        --добавить в список
        GLOBAL_JTAC_UNITS[jtacGroupName] = jtacUnit:getName()

    end
	
-- Поиск текущего Юнита

    if jtacUnit:isActive() == false then

        cleanupJTAC(jtacGroupName)
        env.info(jtacGroupName .. ' Не активно - Ожидание 30 секунд')
		GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer] = timer.scheduleFunction(timerJLase, { jtacGroupName, laserCode,smoke,lock,colour,targetGroupName, _time}, timer.getTime() + 30)
    return
    end

    local enemyUnit = getCurrentUnit(jtacUnit, jtacGroupName)
	
    if enemyUnit == nil and GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] ~= nil then
		

        local tempUnitInfo = GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]
        local tempUnit = Unit.getByName(tempUnitInfo.name)
        
        
		if tempUnit ~= nil and tempUnit:getLife() > 0 and tempUnit:isActive() == true then
		
		notify(jtacGroupName .. ": Цель " .. tempUnitInfo.unitType .. ": Цель ", showTimeMax)
        else
        notify(jtacGroupName .. ": Цель " .. tempUnitInfo.unitType .. " уничтожена. Хорошая работа! ", showTimeMax)
        end

        --удалить из списка дымов
        GLOBAL_JTAC_SMOKE[tempUnitInfo.name] = nil

        -- удалить из списка целей
        GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = nil
        --стоп подсвет
        cancelLase(jtacGroupName)

    end

    if enemyUnit == nil then

    	enemyUnit = findNearestVisibleEnemy(jtacUnit,lock,targetGroupName) 

        if enemyUnit ~= nil then

		            -- store current target for easy lookup
            GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = { name = enemyUnit:getName(), unitType = enemyUnit:getTypeName(), unitId = enemyUnit:getID() }
        
	     	GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] = false
            if lock == "static" then GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] = true end

			
			if _time>0  and GLOBAL_JTAC_TIMER[jtacGroupName]==nil then GLOBAL_JTAC_TIMER[jtacGroupName] = timer.scheduleFunction(timerStopJTAC, {jtacGroupName}, timer.getTime() + _time)  
			                          
									  end		--------------------------  ТАЙМЕР
		    local msg = jtacGroupName .. ": Подсвечиваю новую цель " .. enemyUnit:getTypeName() .. ', код лазера: ' .. laserCode .. "\n" .. getPositionString(enemyUnit)
			if _time>0 then  msg = msg .. "\nдлительность подсвета - " .. _time .. " сек. (" .. roundNumber (_time/60,2) .. " мин.)" end
			notify(msg, showTimeMax)
	        
            -- создать дым
            if smoke == true then

                --создание первого дыма
               createSmokeMarker(enemyUnit,colour)
            end
            else trigger.action.outText(jtacGroupName .. ": нет видимых целей.", showTimeMax) StopJTAC(jtacGroupName) end
    end


	
    if enemyUnit ~= nil then

        laseUnit(enemyUnit, jtacUnit, jtacGroupName, laserCode)

        GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer] = timer.scheduleFunction(timerJLase, { jtacGroupName, laserCode, smoke, lock, colour, targetGroupName, _time }, timer.getTime() + 1) 
		if smoke == true then
            local nextSmokeTime = GLOBAL_JTAC_SMOKE[enemyUnit:getName()]

            --recreate smoke marker after 5 mins
            if nextSmokeTime ~= nil and nextSmokeTime < timer.getTime() then

                createSmokeMarker(enemyUnit, colour)
            end
        end

    else
        -- stop lazing the old spot
        cancelLase(jtacGroupName)
		if enemyUnit ~= nil then GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer] = timer.scheduleFunction(timerJLase, { jtacGroupName, laserCode, smoke,lock,colour,targetGroupName, _time }, timer.getTime() + 5) end

		end
end


-- таймер СТОП
function timerStopJTAC(args)
    StopJTAC(args[1])
end


function StopAllJTAC() -- ОСТАНОВКА ВСЕХ ПАН
	for key,value in pairs(GLOBAL_JTAC_UNITS) do
    StopJTAC(key)
    end
	notify ("All JTAC stop.", showTimeMin)
end

function StopJTAC(jtacGroupName) -- ОСТАНОВКА УКАЗАННОГО ПАН
	
 	
    if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil then timer.removeFunction(GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName][timer]); 	 
                                                                                                        	notify (jtacGroupName .. ": подсвет закончил", showTimeMin) end
																											
 																											
																											
 	if GLOBAL_JTAC_TIMER~=nil and GLOBAL_JTAC_TIMER[jtacGroupName]~=nil then  timer.removeFunction(GLOBAL_JTAC_TIMER[jtacGroupName])  
																															   GLOBAL_JTAC_TIMER[jtacGroupName] = nil  end -- СПИСОК ТАЙМЕРА
 
																															   
	if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil then cleanupJTAC(jtacGroupName) end
	
 
	
    if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil then GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = nil end
 
	
	if GLOBAL_JTAC_UNIT_VISIBLE~=nil then zeroJtac(jtacGroupName) end
end



-- used by the timer function
function timerJLase(args)
    JLaseStart(args[1], args[2], args[3],args[4],args[5],args[6],args[7]) 
end

function cleanupJTAC(jtacGroupName)
    -- clear laser - just in case
    cancelLase(jtacGroupName)

    -- Cleanup
    GLOBAL_JTAC_UNITS[jtacGroupName] = nil
    GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] = nil
end

function notify(message, displayFor)
    trigger.action.outTextForCoalition(SIDE_COALITION, message, displayFor)
    -- trigger.action.outSoundForCoalition(SIDE_COALITION, "radiobeep.ogg")
end

function createSmokeMarker(enemyUnit,colour)

    --recreate in 5 mins
    GLOBAL_JTAC_SMOKE[enemyUnit:getName()] = timer.getTime() + 300.0

    -- move smoke 2 meters above target for ease
    local enemyPoint = enemyUnit:getPoint()
    trigger.action.smoke({ x = enemyPoint.x, y = enemyPoint.y + 2.0, z = enemyPoint.z }, colour)
end

function cancelLase(jtacGroupName)

    local tempLase = GLOBAL_JTAC_LASE[jtacGroupName]

    if tempLase ~= nil then
        Spot.destroy(tempLase)
        GLOBAL_JTAC_LASE[jtacGroupName] = nil

        tempLase = nil
    end

    local tempIR = GLOBAL_JTAC_IR[jtacGroupName]

    if tempIR ~= nil then
        Spot.destroy(tempIR)
        GLOBAL_JTAC_IR[jtacGroupName] = nil
        tempIR = nil
    end
end

function laseUnit(enemyUnit, jtacUnit, jtacGroupName, laserCode)

    --cancelLase(jtacGroupName)

    local spots = {}

    local enemyVector = enemyUnit:getPoint()
    local enemyVectorUpdated = { x = enemyVector.x, y = enemyVector.y + 2.0, z = enemyVector.z }

    local oldLase = GLOBAL_JTAC_LASE[jtacGroupName]
    local oldIR = GLOBAL_JTAC_IR[jtacGroupName]

    if oldLase == nil or oldIR == nil then

        -- create lase

        local status, result = pcall(function()
            spots['irPoint'] = Spot.createInfraRed(jtacUnit, { x = 0, y = 2.0, z = 0 }, enemyVectorUpdated)
            spots['laserPoint'] = Spot.createLaser(jtacUnit, { x = 0, y = 2.0, z = 0 }, enemyVectorUpdated, laserCode)
            return spots
        end)

        if not status then
            env.error('ERROR: ' .. assert(result), false)
        else
            if result.irPoint then

                --    env.info(jtacUnit:getName() .. ' placed IR Pointer on '..enemyUnit:getName())

                GLOBAL_JTAC_IR[jtacGroupName] = result.irPoint --store so we can remove after

            end
            if result.laserPoint then

                --	env.info(jtacUnit:getName() .. ' is Lasing '..enemyUnit:getName()..'. CODE:'..laserCode)

                GLOBAL_JTAC_LASE[jtacGroupName] = result.laserPoint
            end
        end

    else

        -- update lase

        if oldLase~=nil then
            oldLase:setPoint(enemyVectorUpdated)
        end

        if oldIR ~= nil then
            oldIR:setPoint(enemyVectorUpdated)
        end

    end

end

-- получить выбранный в данный момент юнит и проверить, что он все еще досигаем
function getCurrentUnit(jtacUnit, jtacGroupName)
    local unit = nil

	-- Проверяем на статический объект
	local isStatic=false
	if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil and GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] == true then isStatic=true end
	---------------------------------------
	
    if GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName] ~= nil then
        unit = Unit.getByName(GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName].name)
    end
	
	if isStatic == true then  unit = StaticObject.getByName(GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName].name) end


    local tempPoint = nil
    local tempDist = nil
    local tempPosition = nil

    local jtacPosition = jtacUnit:getPosition()
    local jtacPoint = jtacUnit:getPoint()

	
    if (isStatic == true  and unit ~= nil and unit:getLife()>0) or (unit ~= nil and unit:getLife() > 0 and unit:isActive() == true) then

        -- вычислить дистанцию
        tempPoint = unit:getPoint()

        tempDist = getDistance(tempPoint.x, tempPoint.z, jtacPoint.x, jtacPoint.z)
        if tempDist < JTAC_maxDistance then
            -- вычислить видимость

            -- check slightly above the target as rounding errors can cause issues, plus the unit has some height anyways
            local offsetEnemyPos = { x = tempPoint.x, y = tempPoint.y + 2.0, z = tempPoint.z }
            local offsetJTACPos = { x = jtacPoint.x, y = jtacPoint.y + 2.0, z = jtacPoint.z }

            if land.isVisible(offsetEnemyPos, offsetJTACPos) then
                return unit
            end
        end
    end
    return nil
end

-- ПОИСК 
-- Найти ближайшую цель для JTAC, что не заблокирована местностью
function findNearestVisibleEnemy(jtacUnit, targetType,targetGroupName)

    local x = 1
    local i = 1

    local units = nil
	
    local groupName = targetGroupName

    local nearestUnit = nil
    
	local nearestDistance = JTAC_maxDistance


    local jtacPoint = jtacUnit:getPoint()
    local jtacPosition = jtacUnit:getPosition()

    local tempPoint = nil
    local tempPosition = nil

    local tempDist = nil

	local enemyCOALITION = nil
	
	local isStatic = false
	if targetType == "static" then isStatic=true end
	
	
	-- Получить все группы каолиции
	 if isStatic~=true then
	 if SIDE_COALITION == coalition.side.RED then 
	     enemyCOALITION = coalition.getGroups(coalition.side.BLUE, Group.Category.GROUND) 
		 else enemyCOALITION = coalition.getGroups(coalition.side.RED, Group.Category.GROUND) end
     else
		 if SIDE_COALITION == coalition.side.RED then
		 enemyCOALITION=coalition.getStaticObjects(coalition.side.BLUE) 
		 else enemyCOALITION = coalition.getStaticObjects(coalition.side.RED) end
     end


    -- Цикл групп
	    for i = 1, #enemyCOALITION do

	if targetGroupName == "all"  then  groupName = enemyCOALITION[i]:getName() end     -- Выбраны все
   	if isStatic == true then units=enemyCOALITION else units = getGroup(groupName) end -- Выбран статик или группа
		
		if groupName~= nil or isStatic == true then

		if #units > 0 then
    -- Цикл юнитов
                for x = 1, #units do
	-- проверка, JTAC уже разработал или нет по этому юниту
                    local targeted = alreadyTarget(jtacUnit,units[x])
                    local allowedTarget = true
    			    
                    if targetType == "vehicle" then
                        
                        allowedTarget = isVehicle(units[x])

                    elseif targetType == "troop" then

                        allowedTarget = isInfantry(units[x])

					elseif targetType == "sam" then

                        allowedTarget = isSam(units[x])
						
					elseif targetType == "armor" then

                        allowedTarget = isArmor(units[x])

            		elseif targetType == "artillery" then

                        allowedTarget = isArtillery(units[x])

    				elseif targetType == "build" then

                        allowedTarget = isBuild(units[x])
						
						
					elseif isStatic == true and targetGroupName~="all" and targetGroupName ~= units[x]:getName() then -- Статик
					
                        allowedTarget = false	
						
                   	end
                
     				if (isStatic == true or units[x]:isActive() == true) and targeted == false and allowedTarget == true then
                        -- вычислить дистанцию
                        tempPoint = units[x]:getPoint()
                        tempDist = getDistance(tempPoint.x, tempPoint.z, jtacPoint.x, jtacPoint.z)
                        if tempDist < JTAC_maxDistance and tempDist < nearestDistance then
                            local offsetEnemyPos = { x = tempPoint.x, y = tempPoint.y + 2.0, z = tempPoint.z }
                            local offsetJTACPos = { x = jtacPoint.x, y = jtacPoint.y + 2.0, z = jtacPoint.z }
                            -- вычислить видимость
                            if land.isVisible(offsetEnemyPos, offsetJTACPos) then

                                nearestDistance = tempDist
                                nearestUnit = units[x]
                             end

                        end
                    end
                end
            end
        end
    end
    


    if nearestUnit == nil then
        return nil
    end


    return nearestUnit
end

function alreadyTarget(jtacUnit, enemyUnit)

    for y , jtacTarget in pairs(GLOBAL_JTAC_CURRENT_TARGETS) do

        if jtacTarget.unitId == enemyUnit:getID() then

            return true
        end

    end

    return false

end

-- Returns only alive units from group but the group / unit may not be active

function getGroup(groupName)

    local groupUnits = Group.getByName(groupName)

    local filteredUnits = {} --contains alive units
    local x = 1

    if groupUnits ~= nil then

        groupUnits = groupUnits:getUnits()

        if groupUnits ~= nil and #groupUnits > 0 then
            for x = 1, #groupUnits do
                if groupUnits[x]:getLife() > 0 then
                    table.insert(filteredUnits, groupUnits[x])
                end
            end
        end
    end

    return filteredUnits
end

-- Distance measurement between two positions, assume flat world

function getDistance(xUnit, yUnit, xZone, yZone)
    local xDiff = xUnit - xZone
    local yDiff = yUnit - yZone

    return math.sqrt(xDiff * xDiff + yDiff * yDiff)
end

-- gets the JTAC status and displays to coalition units
function getJTACStatus(args)
    local coalition = args[1]
    local gID = args[2]
	
    local jtacGroupName = nil
    local jtacUnit = nil
    local jtacUnitName = nil

	
    local message = "///// СТАТУС ГРУПП JTAC: \n"

    for jtacGroupName, jtacUnitName in pairs(GLOBAL_JTAC_UNITS) do
        --look up units
        jtacUnit = Unit.getByName(jtacUnitName)

        if jtacUnit ~= nil and jtacUnit:getLife() > 0 and jtacUnit:isActive() == true then

            local enemyUnit = getCurrentUnit(jtacUnit, jtacGroupName)

            local laserCode =  GLOBAL_JTAC_LASER_CODES[jtacGroupName]

            if laserCode == nil then
            	laserCode = "UNKNOWN"
            end
            if enemyUnit ~= nil and enemyUnit:getLife() > 0 and ((GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]~=nil and GLOBAL_JTAC_CURRENT_TARGETS[jtacGroupName]["isStatic"] == true) or enemyUnit:isActive() == true) then
--            if enemyUnit ~= nil and enemyUnit:getLife() > 0 and enemyUnit:isActive() == true then
                message = message .. "\n" .. jtacGroupName .. ": Цель " .. enemyUnit:getTypeName().. ", код лазера: " .. laserCode .. "\n" .. getPositionString(enemyUnit) .. "\n"
            else
			   if GLOBAL_JTAC_UNITS[jtacGroupName]~=nil then message = message .. "\n" .. jtacGroupName .. ": Цели в радиусе " .. JTAC_maxDistance/1000 .. " км. не обнаружены, работу закончил. \nМои " .. getPositionString(jtacUnit) .."\n" end
			end
        end
    end
    trigger.action.outTextForGroup(gID, message, showTimeMax, true)   
		
end

function TableConcat(t1,t2)
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function zeroJtac(jtacGroupName)
	   for k, v in pairs(GLOBAL_JTAC_UNIT_VISIBLE) do
        GLOBAL_JTAC_UNIT_VISIBLE[k]["jtac"][jtacGroupName]=nil 
       end
end

-- Radio command for players (F10 Menu)
function addRadioCommands()
    timer.scheduleFunction(addRadioCommands, nil, timer.getTime() + 10)
    local blueGroups = coalition.getGroups(SIDE_COALITION)
    local x = 1

    if blueGroups ~= nil then
        for x, tmpGroup in pairs(blueGroups) do
            local index = "GROUP_" .. Group.getID(tmpGroup)
            if GLOBAL_JTAC_RADIO_ADDED[index] == nil then
			missionCommands.addCommandForGroup(Group.getID(tmpGroup), "Статус ПАН (JTAC)", nil, getJTACStatus, {1, Group.getID(tmpGroup)})
                GLOBAL_JTAC_RADIO_ADDED[index] = true
            end
        end
    end
end

function isBuild(unit) -- Укрепление

 if unit:getDesc()["attributes"]["Fortifications"]==true then return true  end
 return false

end

function isArmor(unit) -- Бронетехника

 if unit:getDesc()["attributes"]["Armored vehicles"]==true then return true  end
 return false

end

function isArtillery(unit) -- Артилерия

 if unit:getDesc()["attributes"]["Artillery"]==true then return true end
 return false

end

function isInfantry(unit)

    local typeName = unit:getTypeName()

    --type coerce tostring
    typeName = string.lower(typeName.."")

    local soldierType = { "infantry","paratrooper","stinger","manpad"}

    for key,value in pairs(soldierType) do
        if string.match(typeName, value) then
            return true
        end
    end

    return false

end

function isSam(unit) -- ПВО
 
 if unit:getDesc()["attributes"]["Air Defence"]==true then return true end
 return false
 
end

-- assume anything that isnt soldier is vehicle
function isVehicle(unit)

    if isInfantry(unit) then
        return false
    end

    return true

end
    
	
function getPositionString(unit)

    if JTAC_location == false then
        return ""
    end

	local latLngStr = latLngString(unit,3)

	local mgrsString = MGRSString(coord.LLtoMGRS(coord.LOtoLL(unit:getPosition().p)),5)

	return "координаты " .. latLngStr .. " - MGRS "..mgrsString

end

-- source of Function MIST - https://github.com/mrSkortch/MissionScriptingTools/blob/master/mist.lua
function latLngString(unit, acc)

	local lat, lon = coord.LOtoLL(unit:getPosition().p)

	local latHemi, lonHemi
	if lat > 0 then
		latHemi = 'N'
	else
		latHemi = 'S'
	end
	
	if lon > 0 then
		lonHemi = 'E'
	else
		lonHemi = 'W'
	end
	
	lat = math.abs(lat)
	lon = math.abs(lon)
	
	local latDeg = math.floor(lat)
	local latMin = (lat - latDeg)*60
	
	local lonDeg = math.floor(lon)
	local lonMin = (lon - lonDeg)*60
	
  -- degrees, decimal minutes.
	latMin = roundNumber(latMin, acc)
	lonMin = roundNumber(lonMin, acc)
	
	if latMin == 60 then
		latMin = 0
		latDeg = latDeg + 1
	end
		
	if lonMin == 60 then
		lonMin = 0
		lonDeg = lonDeg + 1
	end
	
	local minFrmtStr -- create the formatting string for the minutes place
	if acc <= 0 then  -- no decimal place.
		minFrmtStr = '%02d'
	else
		local width = 3 + acc  -- 01.310 - that's a width of 6, for example.
		minFrmtStr = '%0' .. width .. '.' .. acc .. 'f'
	end
	
	return string.format('%02d', latDeg) .. ' ' .. string.format(minFrmtStr, latMin) .. '\'' .. latHemi .. '   '
   .. string.format('%02d', lonDeg) .. ' ' .. string.format(minFrmtStr, lonMin) .. '\'' .. lonHemi

end

-- source of Function MIST - https://github.com/mrSkortch/MissionScriptingTools/blob/master/mist.lua
 function MGRSString(MGRS, acc) 
	if acc == 0 then
		return MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph
	else
		return MGRS.UTMZone .. ' ' .. MGRS.MGRSDigraph .. ' ' .. string.format('%0' .. acc .. 'd', roundNumber(MGRS.Easting/(10^(5-acc)), 0)) 
		       .. ' ' .. string.format('%0' .. acc .. 'd', roundNumber(MGRS.Northing/(10^(5-acc)), 0))
	end
end
-- From http://lua-users.org/wiki/SimpleRound
 function roundNumber(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end


-- добавление радиокоманды
if JTAC_jtacStatusF10 == true then
    timer.scheduleFunction(addRadioCommands, nil, timer.getTime() + 1)
end
env.setErrorMessageBoxEnabled(errorShow)
trigger.action.outText('JLase Beta by Eagle86', showTimeMin);
