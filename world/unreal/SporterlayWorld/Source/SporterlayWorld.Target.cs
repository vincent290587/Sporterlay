using UnrealBuildTool;

public class SporterlayWorldTarget : TargetRules
{
	public SporterlayWorldTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Game;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("SporterlayWorld");
	}
}
