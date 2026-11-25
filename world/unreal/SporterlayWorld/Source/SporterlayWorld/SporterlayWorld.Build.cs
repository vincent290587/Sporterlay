using UnrealBuildTool;

public class SporterlayWorld : ModuleRules
{
	public SporterlayWorld(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] {
			"Core", "CoreUObject", "Engine", "InputCore",
			"Sockets", "Networking", "Json", "XmlParser",
		});
	}
}
