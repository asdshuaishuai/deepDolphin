// EngineStub.kt —— 判据用引擎桩：AgentCore 必填校验的执行点在引擎调用**之前**，
// 校验失败根本走不到引擎调用（桩永远不会真执行）。

package canopy.engine

class EngineStub : Engine("stub-nonexistent")

val EngineStubInstance = EngineStub()
