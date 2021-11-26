if SERVER then
	AddCSLuaFile()

	AddCSLuaFile("includes/modules/pacoman.lua")
	AddCSLuaFile("pacoman/client/cl_pacoman_ui.lua")

	-- add resources
	resource.AddFile("materials/vgui/pacoman/ic_setting.vmt")
	resource.AddFile("materials/vgui/pacoman/ic_namespace.vmt")
	resource.AddFile("materials/vgui/pacoman/ic_add.vmt")
	resource.AddFile("materials/vgui/pacoman/ic_remove.vmt")
else
	include("pacoman/client/cl_pacoman_ui.lua")
end

