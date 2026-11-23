using UnrealBuildTool;

public class SporterlayWorldEditorTarget : TargetRules
{
	public SporterlayWorldEditorTarget(TargetInfo Target) : base(Target)
	{
		Type = TargetType.Editor;
		DefaultBuildSettings = BuildSettingsVersion.Latest;
		IncludeOrderVersion = EngineIncludeOrderVersion.Latest;
		ExtraModuleNames.Add("SporterlayWorld");
	}
}
