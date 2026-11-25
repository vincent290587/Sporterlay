#include "RiderPawn.h"

#include "Camera/CameraComponent.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "EngineUtils.h"
#include "RideRoute.h"
#include "SporterlayLink.h"

namespace
{
	constexpr float Gravity = 9.81f;
	constexpr float WheelInertiaKg = 1.0f;  // two wheels' rotational inertia, as extra mass
	constexpr float MinDriveSpeed = 1.0f;   // m/s; caps the push force P / v when starting off
	constexpr float MaxSpeed = 30.0f;       // m/s, ~108 km/h
	constexpr float PhysicsStep = 1.0f / 120.0f;
}

ARiderPawn::ARiderPawn()
{
	PrimaryActorTick.bCanEverTick = true;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(RootComponent);
	Camera->SetFieldOfView(85.0f);
	AutoPossessPlayer = EAutoReceiveInput::Player0;
}

void ARiderPawn::BeginPlay()
{
	Super::BeginPlay();
	Link = GetWorld()->GetSubsystem<USporterlayLink>();
	if (!Route)
	{
		for (TActorIterator<ARideRoute> It(GetWorld()); It; ++It)
		{
			Route = *It;
			break;
		}
	}
}

void ARiderPawn::Integrate(float Watts, float Dt)
{
	// m dv/dt = P/v - m g (sin a + Crr cos a) - 1/2 rho CdA v^2
	const float Angle = FMath::Atan(Grade / 100.0f);
	const float Drive = Watts * DrivetrainEfficiency / FMath::Max(Speed, MinDriveSpeed);
	const float Resist = TotalMassKg * Gravity * (FMath::Sin(Angle) + Crr * FMath::Cos(Angle))
		+ 0.5f * AirDensity * CdA * Speed * Speed;
	const float Accel = (Drive - Resist) / (TotalMassKg + WheelInertiaKg);
	Speed = FMath::Clamp(Speed + Accel * Dt, 0.0f, MaxSpeed);
	// rolling resistance can't push you backwards: at a standstill on the flat, stay put
	if (Speed < 0.05f && Watts <= 0.0f && Grade >= 0.0f)
	{
		Speed = 0.0f;
	}
}

void ARiderPawn::Place(float Dt)
{
	const FVector Ground = Route->LocationAt(Distance) + Route->RightAt(Distance) * LaneOffset;
	const FVector AheadGround = Route->LocationAt(Distance + LookAhead) + Route->RightAt(Distance + LookAhead) * LaneOffset;
	const FVector Eye = Ground + FVector(0.0f, 0.0f, EyeHeight);
	FRotator Look = (AheadGround - Ground).Rotation();
	Look.Roll = 0.0f;
	// gentle turn-in, but snap on the first frame
	const FRotator Rot = bPlaced ? FMath::RInterpTo(GetActorRotation(), Look, Dt, 4.0f) : Look;
	SetActorLocationAndRotation(Eye, Rot);
	bPlaced = true;
}

void ARiderPawn::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (!Route)
	{
		if (bShowDebugText && GEngine)
		{
			GEngine->AddOnScreenDebugMessage(1, 0.0f, FColor::Orange, TEXT("No RideRoute in this level: place one and draw its spline"));
		}
		return;
	}
	const USporterlayLink* L = Link.Get();
	const float Watts = L ? L->GetPower() : 0.0f;

	// grade follows the road with ~1 s lag, so a kink in the spline isn't a jolt
	const float TargetGrade = FMath::Clamp(Route->GradeAt(Distance), -25.0f, 25.0f);
	Grade = FMath::FInterpTo(Grade, TargetGrade, DeltaSeconds, 1.0f);

	// fixed sub-steps: frame time varies a lot, the integration shouldn't
	float Left = FMath::Min(DeltaSeconds, 0.25f);
	while (Left > 0.0f)
	{
		const float Dt = FMath::Min(Left, PhysicsStep);
		Integrate(Watts, Dt);
		Distance += Speed * 100.0f * Dt;
		Odometer += Speed * 100.0f * Dt;
		Left -= Dt;
	}
	const float RouteLength = Route->Length();
	Distance = Route->WrapDistance(Distance);
	if (Distance >= RouteLength && RouteLength > 0.0f)  // end of an open route
	{
		Speed = 0.0f;
	}
	Place(DeltaSeconds);

	if (bShowDebugText && GEngine)
	{
		const FString Status = !L ? TEXT("no link")
			: !L->GetError().IsEmpty() ? L->GetError()
			: L->IsConnected() ? TEXT("Sporterlay") : TEXT("waiting for Sporterlay (tray > Extras > Send power to the virtual world)");
		GEngine->AddOnScreenDebugMessage(1, 0.0f, FColor::White, FString::Printf(
			TEXT("%.0f W   %.1f km/h   %+.1f %%   %.2f km   [%s]"), Watts, Speed * 3.6f, Grade, GetDistanceKm(), *Status));
	}
}
