//
// Control computer for point defense batteries.
// Handles control UI, but also coordinates their fire to avoid overkill.
//

/obj/machinery/pointdefense_control
	name = "fire assist mainframe"
	desc = "A specialized computer designed to synchronize a variety of weapon systems and a vessel's astronav data."
	icon = 'icons/obj/artillery.dmi'
	icon_state = "control"
	var/ui_template = "pointdefense_control.tmpl"
	var/initial_id_tag
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/weapon/circuitboard/pointdefense_control
	// base_type =       /obj/machinery/pointdefense_control
	// construct_state = /decl/machine_construction/default/panel_closed
	var/list/targets = list()  // Targets being engaged by associated batteries
	var/datum/local_network/lan

/obj/machinery/pointdefense_control/Initialize()
	. = ..()
	if(initial_id_tag)
		lan = update_local_network(src, initial_id_tag)
		//No more than 1 controller please.
		if(lan)
			var/list/pointdefense_controllers = lan.get_devices(/obj/machinery/pointdefense_control)
			if(pointdefense_controllers.len > 1)
				lan.remove_device(src)
				lan = null
	return INITIALIZE_HINT_LATELOAD

// TODO - Stop this once machines are converted to Initialize
/obj/machinery/pointdefense/LateInitialize()
	default_apply_parts()

/obj/machinery/pointdefense_control/Destroy()
	if(lan)
		lan.remove_device(src)
		lan = null
	. = ..()

/obj/machinery/pointdefense_control/ui_interact(var/mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	if(ui_template)
		var/list/data = build_ui_data()
		ui = SSnanoui.try_update_ui(user, src, ui_key, ui, data, force_open)
		if (!ui)
			ui = new(user, src, ui_key, ui_template, name, 400, 600)
			ui.set_initial_data(data)
			ui.open()
			ui.set_auto_update(1)

/obj/machinery/pointdefense_control/attack_ai(mob/user)
	if(CanUseTopic(user, global.default_state) > STATUS_CLOSE)
		ui_interact(user)
		return TRUE

/obj/machinery/pointdefense_control/attack_hand(mob/user)
	if((. = ..()))
		return
	if(CanUseTopic(user, global.default_state) > STATUS_CLOSE)
		ui_interact(user)
		return TRUE

// TODO - Remove this shim once OnTopic is implemented for machinery
/obj/machinery/pointdefense_control/Topic(var/href, var/href_list = list(), var/datum/topic_state/state)
	if((. = ..()))
		return
	state = state || global.default_state
	if(CanUseTopic(usr, state, href_list) == STATUS_INTERACTIVE)
		CouldUseTopic(usr)
		return OnTopic(usr, href_list, state)
	CouldNotUseTopic(usr)
	return TRUE

/obj/machinery/pointdefense_control/proc/OnTopic(var/mob/user, var/href_list, var/datum/topic_state/state)
	if(href_list["toggle_active"])
		var/obj/machinery/pointdefense/PD = locate(href_list["toggle_active"])
		if(!istype(PD))
			return TOPIC_NOACTION

		if(!lan || !lan.is_connected(PD))
			return TOPIC_NOACTION

		if(!(get_z(PD) in GetConnectedZlevels(get_z(src))))
			to_chat(user, "<span class='warning'>[PD] is not within control range.</span>")
			return TOPIC_NOACTION

		if(!PD.Activate()) //Startup() whilst the device is active will return null.
			PD.Deactivate()
		return TOPIC_REFRESH

/obj/machinery/pointdefense_control/proc/build_ui_data()
	var/list/data = list()
	data["id"] = lan ? lan.id_tag : "unset"
	data["name"] = name
	var/list/turrets = list()
	if(lan)
		var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
		var/list/pointdefense_turrets = lan.get_devices(/obj/machinery/pointdefense)
		for(var/i = 1 to LAZYLEN(pointdefense_turrets))
			var/obj/machinery/pointdefense/PD = pointdefense_turrets[i]
			if(!(get_z(PD) in connected_z_levels))
				continue
			var/list/turret = list()
			turret["id"] =          "#[i]"
			turret["ref"] =         "\ref[PD]"
			turret["active"] =       PD.active
			turret["effective_range"] = PD.active ? "[PD.kill_range] meter\s" : "OFFLINE."
			turret["reaction_wheel_delay"] = PD.active ? "[(PD.rotation_speed / (1 SECONDS))] second\s" : "OFFLINE."
			turret["recharge_time"] = PD.active ? "[(PD.charge_cooldown / (1 SECONDS))] second\s" : "OFFLINE."

			turrets += list(turret)

	data["turrets"] = turrets
	return data

/obj/machinery/pointdefense_control/attackby(var/obj/item/W, var/mob/user)
	if(W?.is_multitool())
		var/new_ident = input(user, "Enter a new ident tag.", "[src]", lan?.id_tag) as null|text
		if(new_ident && user.Adjacent(src) && CanInteract(user, physical_state))
			lan = update_local_network(src, new_ident, lan, user)
		//Check if there is more than 1 controller
		if(lan)
			var/list/pointdefense_controllers = lan.get_devices(/obj/machinery/pointdefense_control)
			if(LAZYLEN(pointdefense_controllers) > 1)
				to_chat(user, "<span class='warning'>The [new_ident] local network already has a controller.</span>")
				lan.remove_device(src)
				lan = null
		return
	if(default_deconstruction_screwdriver(user, W))
		return
	if(default_deconstruction_crowbar(user, W))
		return
	if(default_part_replacement(user, W))
		return
	return ..()

//
// The acutal point defense battery
//

/obj/machinery/pointdefense
	name = "\improper point defense battery"
	icon = 'icons/obj/artillery.dmi'
	icon_state = "pointdefense"
	desc = "A Kuiper pattern anti-meteor battery. Capable of destroying most threats in a single salvo."
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/weapon/circuitboard/pointdefense
	idle_power_usage = 0.1 KILOWATTS
	// construct_state = /decl/machine_construction/default/panel_closed
	// maximum_component_parts = list(/obj/item/weapon/stock_parts = 10)         //null - no max. list(type part = number max).
	// base_type = /obj/machinery/pointdefense
	// stock_part_presets = list(/decl/stock_part_preset/terminal_setup)
	// uncreated_component_parts = null
	appearance_flags = PIXEL_SCALE
	var/active = TRUE
	var/charge_cooldown = 1 SECOND  //time between it can fire at different targets
	var/last_shot = 0
	var/kill_range = 18
	var/rotation_speed = 0.25 SECONDS  //How quickly we turn to face threats
	var/engaging = FALSE
	var/initial_id_tag
	var/datum/local_network/lan

/obj/machinery/pointdefense/Initialize()
	. = ..()
	if(initial_id_tag)
		lan = update_local_network(src, initial_id_tag)
	return INITIALIZE_HINT_LATELOAD

// TODO - Stop this once machines are converted to Initialize
/obj/machinery/pointdefense/LateInitialize()
	default_apply_parts()

/obj/machinery/pointdefense/Destroy()
	if(lan)
		lan.remove_device(src)
		lan = null
	. = ..()

/obj/machinery/pointdefense/attackby(var/obj/item/W, var/mob/user)
	if(W?.is_multitool())
		var/new_ident = input(user, "Enter a new ident tag.", "[src]", lan?.id_tag) as null|text
		if(new_ident && user.Adjacent(src) && CanInteract(user, physical_state))
			lan = update_local_network(src, new_ident, lan, user)
		return
	if(default_deconstruction_screwdriver(user, W))
		return
	if(default_deconstruction_crowbar(user, W))
		return
	if(default_part_replacement(user, W))
		return
	return ..()

//Guns cannot shoot through hull or generally dense turfs.
/obj/machinery/pointdefense/proc/space_los(meteor)
	for(var/turf/T in getline(src,meteor))
		if(T.density)
			return FALSE
	return TRUE

/obj/machinery/pointdefense/proc/Shoot(var/weakref/target)
	var/obj/effect/meteor/M = target.resolve()
	if(!istype(M))
		return
	engaging = TRUE
	var/Angle = round(Get_Angle(src,M))
	var/matrix/rot_matrix = matrix()
	rot_matrix.Turn(Angle)
	addtimer(CALLBACK(src, .proc/finish_shot, target), rotation_speed)
	animate(src, transform = rot_matrix, rotation_speed, easing = SINE_EASING)

	set_dir(ATAN2(transform.b, transform.a) > 0 ? NORTH : SOUTH)

/obj/machinery/pointdefense/proc/finish_shot(var/weakref/target)
	//Cleanup from list
	var/obj/machinery/pointdefense_control/PC = null
	if(lan)
		var/list/pointdefense_controllers = lan.get_devices(/obj/machinery/pointdefense_control)
		PC = LAZYACCESS(pointdefense_controllers, 1)
	if(istype(PC))
		PC.targets -= target

	engaging = FALSE
	last_shot = world.time
	var/obj/effect/meteor/M = target.resolve()
	if(!istype(M))
		return
	//We throw a laser but it doesnt have to hit for meteor to explode
	var/obj/item/projectile/beam/pointdefense/beam = new(get_turf(src))
	playsound(src, 'sound/weapons/mandalorian.ogg', 75, 1)
	use_power_oneoff(idle_power_usage * 10)
	beam.launch_projectile(target = M.loc, user = src)

	M.make_debris()
	qdel(M)

/obj/machinery/pointdefense/process()
	..()
	if(stat & (NOPOWER|BROKEN))
		return
	if(!active)
		return
	var/desiredir = ATAN2(transform.b, transform.a) > 0 ? NORTH : SOUTH
	if(dir != desiredir)
		set_dir(desiredir)
	if(engaging || ((world.time - last_shot) < charge_cooldown))
		return

	if(GLOB.meteor_list.len == 0)
		return
	var/list/connected_z_levels = GetConnectedZlevels(get_z(src))
	var/obj/machinery/pointdefense_control/PC = null
	if(lan)
		var/list/pointdefense_controllers = lan.get_devices(/obj/machinery/pointdefense_control)
		PC = LAZYACCESS(pointdefense_controllers, 1)
	if(!istype(PC) || !(get_z(PC) in connected_z_levels))
		return

	for(var/obj/effect/meteor/M in GLOB.meteor_list)
		var/already_targeted = FALSE
		for(var/weakref/WR in PC.targets)
			var/obj/effect/meteor/m = WR.resolve()
			if(m == M)
				already_targeted = TRUE
				break
			if(!istype(m))
				PC.targets -= WR

		if(already_targeted)
			continue

		if(!(M.z in connected_z_levels))
			continue
		if(get_dist(M, src) > kill_range)
			continue
		if(!emagged && space_los(M))
			var/weakref/target = weakref(M)
			PC.targets += target
			Shoot(target)
			return

/obj/machinery/pointdefense/RefreshParts()
	. = ..()
	// Calculates an average rating of components that affect shooting rate
	var/shootrate_divisor = total_component_rating_of_type(/obj/item/weapon/stock_parts/capacitor)

	charge_cooldown = 2 SECONDS / (shootrate_divisor ? shootrate_divisor : 1)

	//Calculate max shooting range
	var/killrange_multiplier = total_component_rating_of_type(/obj/item/weapon/stock_parts/capacitor)
	killrange_multiplier += 1.5 * total_component_rating_of_type(/obj/item/weapon/stock_parts/scanning_module)

	kill_range = 10 + 4 * killrange_multiplier

	var/rotation_divisor = total_component_rating_of_type(/obj/item/weapon/stock_parts/manipulator)
	rotation_speed = 0.5 SECONDS / (rotation_divisor ? rotation_divisor : 1)

/obj/machinery/pointdefense/proc/Activate()
	if(active)
		return FALSE

	active = TRUE
	return TRUE

/obj/machinery/pointdefense/proc/Deactivate()
	if(!active)
		return FALSE
	playsound(src, 'sound/machines/apc_nopower.ogg', 50, 0)
	active = FALSE
	return TRUE

//
// Projectile Beam Definitions
//

/obj/item/projectile/beam/pointdefense
	name = "point defense salvo"
	icon_state = "laser"
	damage = 15
	damage_type = ELECTROCUTE //You should be safe inside a voidsuit
	sharp = FALSE //"Wide" spectrum beam
	light_color = COLOR_GOLD

	muzzle_type = /obj/effect/projectile/muzzle/pointdefense
	tracer_type = /obj/effect/projectile/tracer/pointdefense
	impact_type = /obj/effect/projectile/impact/pointdefense


/obj/effect/projectile/tracer/pointdefense
	icon_state = "beam_pointdef"
	// light_range = 2
	// light_power = 1
	// light_color = COLOR_GOLD

/obj/effect/projectile/muzzle/pointdefense
	icon_state = "muzzle_pointdef"
	// light_range = 2
	// light_power = 1
	// light_color = COLOR_GOLD

/obj/effect/projectile/impact/pointdefense
	icon_state = "impact_pointdef"
	// light_range = 2
	// light_power = 1
	// light_color = COLOR_GOLD
