--[[
    Slyhark (marcos@carpiomeza.eu.org)
	
    W3MMD SCORE API v2.1 - CON ESTADISTICAS POR RAZA (FORMATO DB CORREGIDO)
    Sistema de EXP y Level basado en logs w3mmd_results.log
    
    NUEVA CARACTERISTICA: Actualiza estadisticas por raza cuando hay winner/loser
    METODO: API NATIVA DE PVPGN (TIEMPO REAL)
    FORMATO: Basado en estructura real de base de datos
    
    Formato de log esperado:
    timestamp|gamename|playername|race|flags|pid
    
    Donde:
    - flags = resultado del juego ("winner" = victoria, "loser" = derrota, "" = solo jugo)
    - race = raza jugada ("orc", "human", "undead", "nightelf", "random")
    - pid = slot del jugador (0, 1, 2, etc.)
]]--

-- ============================================================================
-- CONFIGURACION DE BASE DE DATOS Y SISTEMA (EDITABLE)
-- ============================================================================

-- Configuracion del sistema
local RESULTS_LOG_FILE = "C:\\PVPGN\\logs\\w3mmd_results.log"
local LOG_CHECK_INTERVAL = 5

-- Configuracion de EXP por resultado (EDITABLE)
local EXP_REWARDS = {
    ["winner"] = 100,    -- flags="winner" = victoria = 100 EXP
    ["loser"] = 25,      -- flags="loser" = derrota = 25 EXP
    ["played"] = 15      -- flags="" = solo jugo = 15 EXP
}

-- MAPEO DE RAZAS A CAMPOS DE BASE DE DATOS (CORREGIDO)
local RACE_MAPPING = {
    ["human"] = "humans",
    ["orc"] = "orcs", 
    ["undead"] = "undead",
    ["nightelf"] = "nightelves",
    ["random"] = "random"
}

-- Configuraciones del sistema
local DEBUG_ENABLED = true

-- ============================================================================
-- VARIABLES GLOBALES
-- ============================================================================

local last_log_check = 0

-- ============================================================================
-- FUNCIONES AUXILIARES
-- ============================================================================

function split_string(str, delimiter)
    local result = {}
    if not str then return result end
    
    -- Version corregida que maneja campos vacios correctamente
    local s = str .. delimiter
    for match in s:gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    
    return result
end

-- ============================================================================
-- FUNCIONES DE ARCHIVO
-- ============================================================================

function file_exists(filename)
    local file = io.open(filename, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function read_all_lines(filename)
    local file = io.open(filename, "r")
    if not file then return nil end
    
    local lines = {}
    for line in file:lines() do
        table.insert(lines, line)
    end
    file:close()
    
    return lines
end

function write_remaining_lines(lines)
    local file = io.open(RESULTS_LOG_FILE, "w")
    if not file then
        if DEBUG_ENABLED then
            print("[W3MMD] No se pudo escribir " .. RESULTS_LOG_FILE)
        end
        return
    end
    
    for _, line in ipairs(lines) do
        file:write(line .. "\n")
    end
    file:close()
end

-- ============================================================================
-- FUNCIONES DE DATOS CON API NATIVA (REEMPLAZO DE MySQL)
-- ============================================================================

function get_current_exp(playername)
    -- USAR API NATIVA con formato de DB real
    local exp = api.account_get_attr(playername, "Record\\W3XP_solo_xp", attr_type_num)
    return exp or 0
end

function get_current_level(playername)
    -- USAR API NATIVA con formato de DB real
    local level = api.account_get_attr(playername, "Record\\W3XP_solo_level", attr_type_num)
    return level or 1
end

function get_current_wins(playername)
    -- USAR API NATIVA con formato de DB real
    local wins = api.account_get_attr(playername, "Record\\W3XP_solo_wins", attr_type_num)
    return wins or 0
end

function get_current_losses(playername)
    -- USAR API NATIVA con formato de DB real
    local losses = api.account_get_attr(playername, "Record\\W3XP_solo_losses", attr_type_num)
    return losses or 0
end

function get_current_race_wins(playername, race)
    -- OBTENER WINS POR RAZA (FORMATO DB REAL)
    local race_field = RACE_MAPPING[string.lower(race)]
    if not race_field then return 0 end
    
    local race_wins = api.account_get_attr(playername, "Record\\W3XP_" .. race_field .. "_wins", attr_type_num)
    return race_wins or 0
end

function get_current_race_losses(playername, race)
    -- OBTENER LOSSES POR RAZA (FORMATO DB REAL)
    local race_field = RACE_MAPPING[string.lower(race)]
    if not race_field then return 0 end
    
    local race_losses = api.account_get_attr(playername, "Record\\W3XP_" .. race_field .. "_losses", attr_type_num)
    return race_losses or 0
end

function calculate_level_from_exp(exp)
    -- Formula de levels (ajustable)
    if exp < 100 then return 1
    elseif exp < 200 then return 2
    elseif exp < 400 then return 3
    elseif exp < 600 then return 4
    elseif exp < 900 then return 5
    elseif exp < 1200 then return 6
    elseif exp < 1600 then return 7
    elseif exp < 2000 then return 8
    elseif exp < 2500 then return 9
    elseif exp < 3000 then return 10
    else return math.min(50, math.floor(exp / 500) + 1) end
end

function update_player_exp_and_stats(playername, result_type, race)
    -- Determinar EXP ganada segun resultado
    local exp_gained = EXP_REWARDS[result_type] or EXP_REWARDS["played"]
    
    -- Obtener datos actuales usando API NATIVA
    local current_exp = get_current_exp(playername)
    local current_wins = get_current_wins(playername)
    local current_losses = get_current_losses(playername)
    
    -- Calcular nuevos valores generales
    local new_exp = current_exp + exp_gained
    local new_level = calculate_level_from_exp(new_exp)
    local new_wins = current_wins
    local new_losses = current_losses
    
    -- Variables para estadisticas por raza
    local current_race_wins = 0
    local current_race_losses = 0
    local new_race_wins = 0
    local new_race_losses = 0
    local race_field = nil
    
    -- LOGICA SEGUN TIPO DE RESULTADO
    local success = true
    
    if result_type == "winner" then
        -- VICTORIA: actualizar wins generales + wins por raza
        new_wins = current_wins + 1
        
        -- Actualizar estadisticas por raza si la raza es valida
        if race and RACE_MAPPING[string.lower(race)] then
            race_field = RACE_MAPPING[string.lower(race)]
            current_race_wins = get_current_race_wins(playername, race)
            new_race_wins = current_race_wins + 1
        end
        
    elseif result_type == "loser" then
        -- DERROTA: actualizar losses generales + losses por raza
        new_losses = current_losses + 1
        
        -- Actualizar estadisticas por raza si la raza es valida
        if race and RACE_MAPPING[string.lower(race)] then
            race_field = RACE_MAPPING[string.lower(race)]
            current_race_losses = get_current_race_losses(playername, race)
            new_race_losses = current_race_losses + 1
        end
    end
    -- Si result_type == "played", solo se actualiza EXP y level (sin wins/losses)
    
    -- ACTUALIZAR USANDO API NATIVA (actualiza memoria + base de datos)
    
    -- Actualizar EXP (siempre)
    if not api.account_set_attr(playername, "Record\\W3XP_solo_xp", attr_type_num, new_exp) then
        success = false
    end
    
    -- Actualizar Level (siempre)
    if not api.account_set_attr(playername, "Record\\W3XP_solo_level", attr_type_num, new_level) then
        success = false
    end
    
    -- Actualizar Wins generales si cambio
    if new_wins ~= current_wins then
        if not api.account_set_attr(playername, "Record\\W3XP_solo_wins", attr_type_num, new_wins) then
            success = false
        end
    end
    
    -- Actualizar Losses generales si cambio
    if new_losses ~= current_losses then
        if not api.account_set_attr(playername, "Record\\W3XP_solo_losses", attr_type_num, new_losses) then
            success = false
        end
    end
    
    -- ACTUALIZAR ESTADISTICAS POR RAZA (FORMATO DB REAL)
    if race_field then
        if result_type == "winner" and new_race_wins > current_race_wins then
            -- Actualizar wins por raza
            if not api.account_set_attr(playername, "Record\\W3XP_" .. race_field .. "_wins", attr_type_num, new_race_wins) then
                success = false
            end
        elseif result_type == "loser" and new_race_losses > current_race_losses then
            -- Actualizar losses por raza
            if not api.account_set_attr(playername, "Record\\W3XP_" .. race_field .. "_losses", attr_type_num, new_race_losses) then
                success = false
            end
        end
    end
    
    if DEBUG_ENABLED then
        local result_text = result_type == "winner" and "VICTORIA" or (result_type == "loser" and "DERROTA" or "PARTIDA")
        local status = success and "ACTUALIZADO" or "ERROR"
        local race_info = ""
        
        if race_field then
            if result_type == "winner" then
                race_info = string.format(" | %s W: %d->%d", race, current_race_wins, new_race_wins)
            elseif result_type == "loser" then
                race_info = string.format(" | %s L: %d->%d", race, current_race_losses, new_race_losses)
            end
        elseif race then
            race_info = " | Raza: " .. race .. " (sin stats)"
        end
        
        print(string.format("[W3MMD-RAZA] %s | %s | +%d EXP | Level:%d | Total:%d | W/L:%d/%d%s | %s", 
            playername, result_text, exp_gained, new_level, new_exp, new_wins, new_losses, race_info, status))
    end
    
    return success
end

-- ============================================================================
-- PROCESAMIENTO DE LOGS
-- ============================================================================

function process_w3mmd_results_log()
    if not file_exists(RESULTS_LOG_FILE) then
        return -- No hay archivo que procesar
    end
    
    -- Leer todas las lineas del archivo
    local lines = read_all_lines(RESULTS_LOG_FILE)
    if not lines or #lines == 0 then
        return
    end
    
    local processed_count = 0
    local remaining_lines = {}
    
    -- Procesar cada linea
    for i, line in ipairs(lines) do
        if process_log_line(line) then
            processed_count = processed_count + 1
            -- Linea procesada exitosamente - no la agregamos a remaining_lines
        else
            -- Error en procesamiento - mantener linea para reintento
            table.insert(remaining_lines, line)
        end
    end
    
    -- Reescribir archivo solo con lineas no procesadas
    write_remaining_lines(remaining_lines)
    
    if processed_count > 0 and DEBUG_ENABLED then
        print("[W3MMD-RAZA] Procesadas " .. processed_count .. " lineas, restantes: " .. #remaining_lines)
    end
end

function process_log_line(line)
    if not line or string.len(line) == 0 then
        return true -- Linea vacia - eliminar
    end
    
    local parts = split_string(line, "|")
    if #parts ~= 6 then
        if DEBUG_ENABLED then
            print("[W3MMD-RAZA] Formato incorrecto (" .. #parts .. " campos): " .. line)
        end
        return false -- Mantener linea para debug
    end
    
    local timestamp = parts[1]
    local gamename = parts[2] 
    local playername = parts[3]
    local race = parts[4]        -- RAZA DEL JUGADOR (Human, Orc, etc.)
    local flags = parts[5]       -- Campo resultado ("winner", "loser", "")
    local pid = tonumber(parts[6]) -- Slot del jugador (no usado para resultado)
    
    if not playername or playername == "" then
        return true
    end
    
    -- VALIDACION ESTRICTA: Si tiene winner/loser pero no tiene raza, eliminar sin procesar
    if (flags == "winner" or flags == "loser") and (not race or race == "") then
        if DEBUG_ENABLED then
            print("[W3MMD-RAZA] ELIMINADO: " .. playername .. " tiene " .. flags .. " pero raza vacia - Datos invalidos")
        end
        return true
    end
    
    -- Interpretar flags para determinar el tipo de resultado
    local result_type
    if flags == "winner" then
        result_type = "winner"   -- Victoria
    elseif flags == "loser" then  
        result_type = "loser"    -- Derrota
    else
        result_type = "played"   -- Solo jugo (flags vacio o cualquier otro valor)
    end
    
    -- Procesar resultado usando API NATIVA CON RAZA
    local success = update_player_exp_and_stats(playername, result_type, race)
    
    if not success and DEBUG_ENABLED then
        print("[W3MMD-RAZA] ERROR: No se pudo actualizar " .. playername)
        return false -- Mantener linea para reintento
    end
    
    return true
end

-- ============================================================================
-- MAINLOOP INTEGRATION
-- ============================================================================

function w3mmd_score_mainloop()
    local current_time = os.time()
    
    -- Verificar archivo cada LOG_CHECK_INTERVAL segundos
    if current_time - last_log_check >= LOG_CHECK_INTERVAL then
        process_w3mmd_results_log()
        last_log_check = current_time
    end
end

-- ============================================================================
-- COMANDO DE VERIFICACION (MEJORADO CON ESTADISTICAS POR RAZA)
-- ============================================================================

function command_w3stats(account, text)
    local target_player = account.name
    local args = split_string(text, " ")
    if args[1] then target_player = args[1] end
    
    -- USAR API NATIVA para obtener datos ACTUALES
    local exp = get_current_exp(target_player)
    local level = get_current_level(target_player)
    local wins = get_current_wins(target_player)
    local losses = get_current_losses(target_player)
    
    local total_games = wins + losses
    local win_ratio = total_games > 0 and math.floor((wins / total_games) * 100) or 0
    
    if exp > 0 or total_games > 0 then
        print(string.format("[STATS-RAZA] %s | Level %d | EXP: %d | W/L: %d/%d (%d%%) | DATOS EN TIEMPO REAL", 
            target_player, level, exp, wins, losses, win_ratio))
        
        -- MOSTRAR ESTADISTICAS POR RAZA
        for race_name, race_field in pairs(RACE_MAPPING) do
            local race_wins = get_current_race_wins(target_player, race_name)
            local race_losses = get_current_race_losses(target_player, race_name)
            if race_wins > 0 or race_losses > 0 then
                local race_total = race_wins + race_losses
                local race_ratio = race_total > 0 and math.floor((race_wins / race_total) * 100) or 0
                print(string.format("[STATS-RAZA] %s %s: %d/%d (%d%%)", 
                    target_player, race_name, race_wins, race_losses, race_ratio))
            end
        end
    else
        print("[STATS-RAZA] No se encontraron stats para: " .. target_player)
    end
    
    return 0
end

-- ============================================================================
-- INICIALIZACION
-- ============================================================================

function w3mmd_score_init()
    if DEBUG_ENABLED then
        print("[W3MMD-RAZA] === SISTEMA W3MMD SCORE v2.1 INICIADO ===")
        print("[W3MMD-RAZA] METODO: API NATIVA DE PVPGN (TIEMPO REAL)")
        print("[W3MMD-RAZA] NUEVA: Estadisticas por raza en winner/loser")
        print("[W3MMD-RAZA] Archivo monitoreado: " .. RESULTS_LOG_FILE)
        print("[W3MMD-RAZA] Victoria (flags='winner'): " .. EXP_REWARDS["winner"] .. " EXP + race stats")
        print("[W3MMD-RAZA] Derrota (flags='loser'): " .. EXP_REWARDS["loser"] .. " EXP + race stats")
        print("[W3MMD-RAZA] Solo jugo (flags=''): " .. EXP_REWARDS["played"] .. " EXP solamente")
        print("[W3MMD-RAZA] Intervalo: " .. LOG_CHECK_INTERVAL .. " segundos")
        print("[W3MMD-RAZA] Mapeo de razas:")
        for race_name, race_field in pairs(RACE_MAPPING) do
            print("[W3MMD-RAZA]   " .. race_name .. " -> W3XP_" .. race_field .. "_wins/losses")
        end
        print("[W3MMD-RAZA] OK ACTUALIZACION INSTANTANEA CON RAZAS HABILITADA")
        print("[W3MMD-RAZA] =======================================")
    end
end