import json 

modelRegistry = {}
reasoningRegistry = {}
Engines = {}
AgentIterationResult = {}
IERCAgentTool = {}
abi = {}

def runNextIteration(modelId, basePrompt, tools, agentReasoning, prompt):
    llm = modelRegistry.get(modelId)
    reasoningEngine = reasoningRegistry.get(Engines.RE_ACT)

    toolsMetadata = [{
        'name': tool.name(), 
        'description': tool.description(),
        'inputDescription': tool.inputDescription()
    } for tool in tools]
    toolsByName = {tool.name: tool for tool in toolsMetadata}
    
    llmPrompt = reasoningEngine.buildPrompt(basePrompt, toolsMetadata, agentReasoning, prompt)
    llmOutput = llm.run(llmPrompt)
    nextStep = reasoningEngine.parse(llmOutput)
    
    if nextStep.isDone():
        return AgentIterationResult(isFinalAnswer=True, finalAnswer=nextStep.answer)
    
    tool = toolsByName.get(nextStep.toolName)
    toolInputByName = {input.name: input for input in tool.inputDescription.paramDescriptions}
    
    params = json.parse(nextStep.params)
    parsedParams = {}

    for param in params.array():
        paramDescription = toolInputByName[param.name]
        parsedParams[param.name] = IERCAgentTool.ParamValue(
            type=paramDescription.type,
            value=abi.encode(param.value, paramDescription.type))

    abiEncodedParams = abi.encode([params.value for params in parsedParams])
    
    return AgentIterationResult(
        isFinalAnswer=False,
        tool=tool,
        toolInput=IERCAgentTool.Input(params=parsedParams, abiEncodedParams=abiEncodedParams),
        agentReasoning=nextStep.reasoning)
