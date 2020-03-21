//
// A utility letting machines "talk" to each other without running into race conditions during initialization.
// Simpler and with less overhead than radio.
// Each local network has a list of entity lists indexed by type path.  Procs let you fetch a list of network members of a given type.
//

GLOBAL_LIST_INIT(local_networks, new)

/datum/local_network
	var/id_tag
	var/list/network_entities =    list()

/datum/local_network/New(var/_id)
	id_tag = _id
	ASSERT(isnull(GLOB.local_networks[id_tag]))
	GLOB.local_networks[id_tag] = src

/datum/local_network/Destroy()
	network_entities.Cut()
	if(GLOB.local_networks[id_tag] == src)
		GLOB.local_networks.Remove(id_tag)
	. = ..()

/datum/local_network/proc/add_device(var/obj/machinery/device)
	var/list/entities = get_devices(device.type)

	if(!entities)
		entities = list()
		network_entities[device.type] = entities

	entities[device] = TRUE

	return entities[device]

/datum/local_network/proc/remove_device(var/obj/machinery/device)
	var/list/entities = get_devices(device.type)
	if(!entities)
		return TRUE

	entities -= device
	if(entities.len <= 0)
		network_entities -= device.type
	if(network_entities.len <= 0)
		qdel(src)
	return isnull(entities[device])

/datum/local_network/proc/is_connected(var/obj/machinery/device)
	var/list/entities = get_devices(device.type)

	if(!entities)
		return FALSE
	return !isnull(entities[device])

/datum/local_network/proc/get_devices(var/device_type)
	for(var/entity_type in network_entities)
		if(ispath(entity_type, device_type))
			return network_entities[entity_type]

// Helper proc for connecting a device to this network with or without a multitool.
/proc/update_local_network(var/holder, var/new_ident, var/datum/local_network/old_lan = null, var/user = null)
	if(old_lan)
		if(old_lan.id_tag == new_ident)
			to_chat(user, "<span class='warning'>\The [holder] is already part of the [new_ident] local network.</span>")
			return old_lan

		if(!old_lan.remove_device(holder))
			to_chat(user, "<span class='warning'>You encounter an error when trying to unregister \the [holder] from the [old_lan.id_tag] local network.</span>")
			return null
		to_chat(user, "<span class='notice'>You unregister \the [holder] from the [old_lan.id_tag] local network.</span>")

	var/datum/local_network/lan = GLOB.local_networks[new_ident]
	if(!lan)
		lan = new(new_ident)
		lan.add_device(holder)
		to_chat(user, "<span class='notice'>You create a new [new_ident] local network and register \the [holder] with it.</span>")
	else
		lan.add_device(holder)
		to_chat(user, "<span class='notice'>You register \the [holder] with the [new_ident] local network.</span>")
	return lan
