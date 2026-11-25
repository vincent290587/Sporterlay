#include "SporterlayLink.h"

#include "Common/UdpSocketBuilder.h"
#include "Dom/JsonObject.h"
#include "HAL/PlatformTime.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Sockets.h"
#include "SocketSubsystem.h"

DEFINE_LOG_CATEGORY_STATIC(LogSporterlay, Log, All);

bool USporterlayLink::DoesSupportWorldType(const EWorldType::Type WorldType) const
{
	return WorldType == EWorldType::Game || WorldType == EWorldType::PIE;
}

void USporterlayLink::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	Socket = FUdpSocketBuilder(TEXT("SporterlayLink"))
		.AsNonBlocking()
		.BoundToAddress(FIPv4Address(127, 0, 0, 1))
		.BoundToPort(Port)
		.WithReceiveBufferSize(64 * 1024)
		.Build();
	if (Socket)
	{
		UE_LOG(LogSporterlay, Log, TEXT("Listening for Sporterlay on udp://127.0.0.1:%d"), Port);
	}
	else
	{
		Error = FString::Printf(TEXT("UDP port %d is busy (another copy running?)"), Port);
		UE_LOG(LogSporterlay, Warning, TEXT("%s"), *Error);
	}
}

void USporterlayLink::Deinitialize()
{
	if (Socket)
	{
		Socket->Close();
		ISocketSubsystem::Get(PLATFORM_SOCKETSUBSYSTEM)->DestroySocket(Socket);
		Socket = nullptr;
	}
	Super::Deinitialize();
}

bool USporterlayLink::IsConnected() const
{
	return FPlatformTime::Seconds() - LastReceived < TimeoutSeconds;
}

void USporterlayLink::Tick(float DeltaTime)
{
	Super::Tick(DeltaTime);
	if (!Socket)
	{
		return;
	}
	uint8 Buffer[2048];
	// Sporterlay sends 4 Hz; drain whatever piled up (a long frame, a hitch) and keep the newest.
	for (int32 i = 0; i < 64; ++i)
	{
		int32 Read = 0;
		if (!Socket->Recv(Buffer, sizeof(Buffer) - 1, Read) || Read <= 0)
		{
			break;
		}
		Buffer[Read] = 0;
		const FString Text = UTF8_TO_TCHAR(reinterpret_cast<const ANSICHAR*>(Buffer));
		TSharedPtr<FJsonObject> Json;
		const TSharedRef<TJsonReader<>> Reader = TJsonReaderFactory<>::Create(Text);
		double Watts = 0.0;
		if (FJsonSerializer::Deserialize(Reader, Json) && Json.IsValid() && Json->TryGetNumberField(TEXT("power"), Watts))
		{
			Power = FMath::Clamp(static_cast<float>(Watts), 0.0f, 3000.0f);
			LastReceived = FPlatformTime::Seconds();
		}
	}
}

TStatId USporterlayLink::GetStatId() const
{
	RETURN_QUICK_DECLARE_CYCLE_STAT(USporterlayLink, STATGROUP_Tickables);
}
