# Adding helper log macros for UE

I for one hate writing UE_LOG() with a bunch of parameters. So I always add something like this in new projects.

In MyGame.cpp
```
DEFINE_LOG_CATEGORY(LogMy);
```

In MyGame.h
```
// this is optional, only needed if you want to expose these to blueprints
UENUM(BlueprintType)
enum class EMyLogLevel : uint8
{
	Log,
	Warning,
	Error
};

#if UE_BUILD_SHIPPING
DECLARE_LOG_CATEGORY_EXTERN(_LogMy, Log, Log)
#else
DECLARE_LOG_CATEGORY_EXTERN(_LogMy, Log, All)
#endif

#define MyDEBUG_CUR_CLASS_FUNC (FString(__FUNCTION__))
#define MYDEBUG_CUR_LINE       (FString::FromInt(__LINE__))
#define MYDEBUG_CUR_CLASS_LINE (MYDEBUG_CUR_CLASS_FUNC + "::" + MYDEBUG_CUR_LINE)
// these are not used but here as an example
#define MYDEBUG_CUR_CLASS      (FString(__FUNCTION__).Left(FString(__FUNCTION__).Find(TEXT(":")))) 
#define MYDEBUG_CUR_FUNC       (FString(__FUNCTION__).Right(FString(__FUNCTION__).Len() - FString(__FUNCTION__).Find(TEXT("::")) - 2))
#define MYDEBUG_CUR_FUNCSIG    (FString(__FUNCSIG__))

#define MYLOGC(LogCat, LogType, FormatString, ...) UE_LOG(LogCat, LogType, TEXT("%s: %s"), *MYDEBUG_CUR_CLASS_LINE, *FString::Printf(TEXT(FormatString), ##__VA_ARGS__))
#define MYLOG(FormatString, ...)      MYLOGC(_LogMY, Display, FormatString, ##__VA_ARGS__)
#define MYERR(FormatString, ...)      MYLOGC(_LogMY, Error, FormatString, ##__VA_ARGS__)
#define MYWARN(FormatString, ...)     MYLOGC(_LogMY, Warning, FormatString, ##__VA_ARGS__)
#define MYVERB(FormatString, ...)     MYLOGC(_LogMY, Verbose, FormatString, ##__VA_ARGS__)
#define MYVERYVERB(FormatString, ...) MYLOGC(_LogMY, VeryVerbose, FormatString, ##__VA_ARGS__)
```

The next two snippets are optional, but I like them a lot. They expose the same logging functionality to blueprints, which makes things just nice and consistent.

In MyBlueprintLibrary.h
```
	UFUNCTION(BlueprintCallable, Category = "MyGame|Debug")
	static void MyLog(EMyLogLevel LoggingLevel, FString Message);
```

In MyBlueprintLibrary.cpp
```
void UMyBPL::MYLog(EMyLogLevel LoggingLevel, FString Message)
{
	switch (LoggingLevel)
	{
		case EMyLogLevel::Log:
			MYLOG("%s", *Message);
			break;
		case EMyLogLevel::Warning:
			MYWARN("%s", *Message);
			break;
		case EMyLogLevel::Error:
			MYERR("%s", *Message);
			break;
		default:
			MYERR("Using invalid log level to log message: %s", *Message);
			break;
	}
}
```