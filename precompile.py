import json 

modelRegistry = {}
reasoningRegistry = {}
Engines = {}
AgentIterationResult = {}
IERCAgentTool = {}
abi = {}

def executeAgent(modelId, agentName, agentDescription, tools, agentReasoning, prompt):
    toolsByName = {tool.name: tool for tool in tools}
    llm = modelRegistry.get(modelId)
    reasoningEngine = reasoningRegistry.get(Engines.RE_ACT)
    
    llmPrompt = reasoningEngine.buildPrompt(agentDescription, tools, agentReasoning, prompt)
    llmOutput = llm.run(llmPrompt)
    nextStep = reasoningEngine.parse(llmOutput)
    
    if nextStep.isDone():
        return AgentIterationResult(isFinalAnswer=True, finalAnswer=nextStep.answer)
    
    tool = toolsByName.get(nextStep.toolName)
    toolInputByName = {input.name: input for input in tool.inputDescription.paramDescriptions}
    
    parsedParams = {}
    params = json.parse(nextStep.params)
    for param in params.array():
        paramDescription = toolInputByName[param.name]
        parsedParams[param.name] = IERCAgentTool.ParamValue(
            type=paramDescription.type,
            abi.encode(param.value, paramDescription.type))
    
    return AgentIterationResult(
        isFinalAnswer=False,
        tool=tool,
        params=parsedParams,
        agentReasoning=nextStep.reasoning)