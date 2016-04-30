const int PROCSKY_STEP_UPDATE = 1000;
float timeToNextProcSkyUpdate = 0;
float psFOV = 89.5f; // It's important to keep this value with nearClip (0.5f) to have nice seamless cubemap 
bool procSkyShow = true;
Node@ procSkyNode;
Node@ procSkyLightNode;
Quaternion procSkyLightNodeLastRotation;
Light@ procSkyLight;
Color procSkyLightColor;
Camera@ procSkyCamera;
Skybox@ procSkySkyBox;
Material@ procSkySkyBoxMaterial;
TextureCube@  procSkyCubeTexture;
RenderPath@ procSkyRenderPath;
int procSkyRenderSize = 512;
int procSkyRenderSizeLast = 0;
bool procSkyRenderQueued = false;
const int MAX_CUBEMAP_FACES = 6;
Array<Quaternion> procSkyFaceRotations;
Array<RenderPathCommand> cmd;
bool dumpingTexCube = false;

Vector3 Kr = Vector3(0.18867780436772762f, 0.4978442963618773f, 0.6616065586417131f); // Absorption profile of air.
float rayleighBrightness = 3.9f;    //3.3f
float mieBrightness = 0.01f;        //0.1f
float spotBrightness = 50.0f;       //50.0f
float scatterStrength = 0.028f;     //0.028f 
float rayleighStrength = 0.139f;    //0.139.0f
float mieStrength = 0.264f;         //0.264f
float rayleighCollectionPower = 0.81f; //0.81f
float mieCollectionPower = 0.39f;   //0.39f
float mieDistribution = 0.63f;      // 0.63f

const String tagLS = "LS";
bool isRenderPathForLSInjected = false;
Texture2D@  LSTextureSunHalo;
Node@ sunOriginNode;
Window@ procSkyWindow;
bool isNewSceneWasOpened = true;
Node@ sunRotateNode;

void ProcSkyCreateWindow() 
{
    procSkyWindow = ui.root.GetChild("ProcSkyWindow", true);
    if (procSkyWindow !is null) return;
    
    procSkyWindow = Window();
    procSkyWindow.name = "ProcSkyWindow";
    procSkyWindow.SetStyleAuto();
    procSkyWindow.movable = true;
    procSkyWindow.resizable = true;
    procSkyWindow.SetLayout(LM_VERTICAL, 2, IntRect(2,2,2,2));
    procSkyWindow.SetAlignment(HA_LEFT, VA_TOP);
    procSkyWindow.opacity = 0.8f;
    
    IntVector2 scrSize(graphics.width, graphics.height);
    IntVector2 winSize(scrSize);
    winSize.x = int(0.3f * winSize.x); winSize.y = int(0.5f * winSize.y);
    IntVector2 uiPos(ui.root.position);
    procSkyWindow.size = IntVector2(500,400);//winSize;
    procSkyWindow.position = IntVector2(50, (scrSize.y - winSize.y) / 2);
    procSkyWindow.visible = true;
    
    ui.root.AddChild(procSkyWindow);
    
    // Create Window 'titlebar' container
    UIElement@ titleBar = UIElement();
    titleBar.SetMinSize(0, 16);
    titleBar.verticalAlignment = VA_TOP;
    titleBar.layoutMode = LM_HORIZONTAL;
    Text@ windowTitle = Text();
    windowTitle.text = "ProcSky Parameters";
    titleBar.AddChild(windowTitle);
    procSkyWindow.AddChild(titleBar);
    windowTitle.SetStyleAuto();
}

Color FromH255S100V100(float h, float s, float v, float a = 1.0f) 
{
    // Gimp HSV color ranges
    h = Clamp(h, 0.0f, 255.0f);
    s = Clamp(s, 0.0f, 100.0f);
    v = Clamp(v, 0.0f, 100.0f);
    
    float normalizedH = h / 255.0f;
    float normalizedS = s / 100.0f;
    float normalizedV = v / 100.0f;
    
    Color ret;
    ret.FromHSV(normalizedH, normalizedS, normalizedV , a);
    return ret;
}

void CheckOrCreateProSkyStuff(bool newOpenedScene, bool procSkyAllStuffTemporary = true) 
{
    if (editorScene is null || procSkyNode is null) return;
    //ProcSkyCreateWindow();
    
    if (procSkyCamera is null || newOpenedScene) 
    {
        procSkyCamera = procSkyNode.CreateComponent("Camera");
        procSkyCamera.fov = psFOV;
        procSkyCamera.farClip = 50.0f;
        procSkyCamera.nearClip = 0.5f;
        procSkyCamera.aspectRatio = 1.0;
        procSkyCamera.temporary = procSkyAllStuffTemporary;
    }
    
    if (procSkyLightNode is null || newOpenedScene) 
    {
        procSkyLightNode = procSkyNode.CreateChild("ProcSkyLightNode");
        procSkyLightNode.worldRotation = Quaternion(40, 180, 0);
        procSkyLightNode.temporary = procSkyAllStuffTemporary;
        
        
        if (procSkyLight is null || newOpenedScene) 
        {   
            procSkyLight = procSkyLightNode.CreateComponent("Light");
            procSkyLight.lightType = LIGHT_DIRECTIONAL;
            procSkyLightColor = FromH255S100V100(57.0f, 9.9f, 73.0f , 1.0);
            procSkyLight.color = procSkyLightColor;
            procSkyLight.temporary = procSkyAllStuffTemporary;
        }
        
        if (sunOriginNode is null || newOpenedScene) 
        {
            sunOriginNode = procSkyLightNode.CreateChild("sunOriginNode");
            sunOriginNode.position = Vector3(0, 0, -100000);
            sunOriginNode.temporary = procSkyAllStuffTemporary;
        }
    }
    
    if (procSkySkyBox is null || newOpenedScene)
    {
        procSkySkyBox = procSkyNode.CreateComponent("Skybox");
        procSkySkyBox.model = cache.GetResource("Model","Models/Box.mdl");
        procSkySkyBoxMaterial = Material();
        procSkySkyBoxMaterial.SetTechnique(0, cache.GetResource("Technique","Techniques/DiffSkyboxLightScatteringMask.xml"));
        procSkySkyBoxMaterial.cullMode = CULL_NONE;
        procSkySkyBox.material = procSkySkyBoxMaterial;
        procSkySkyBox.temporary = procSkyAllStuffTemporary;
        
    }
    
    if (procSkyRenderSizeLast != procSkyRenderSize || newOpenedScene)
    {
        if (SetRenderSize(procSkyRenderSize))
            procSkyRenderSizeLast = procSkyRenderSize;
    }
    
    if (procSkyFaceRotations.length < MAX_CUBEMAP_FACES || newOpenedScene)
    {     
        procSkyFaceRotations.Resize(MAX_CUBEMAP_FACES);
        procSkyFaceRotations[FACE_POSITIVE_X] = Quaternion(0, 90, 0);
        procSkyFaceRotations[FACE_NEGATIVE_X] = Quaternion(0, -90, 0);
        procSkyFaceRotations[FACE_POSITIVE_Y] = Quaternion(-90, 0, 0);
        procSkyFaceRotations[FACE_NEGATIVE_Y] = Quaternion(90, 0, 0);
        procSkyFaceRotations[FACE_POSITIVE_Z] = Quaternion(0, 0, 0);
        procSkyFaceRotations[FACE_NEGATIVE_Z] = Quaternion(0, 180, 0);
    }
    
    if (!isRenderPathForLSInjected) 
    {
        VariantMap atmoParams;
        atmoParams["Kr"] = Kr;
        atmoParams["RayleighBrightness"] = rayleighBrightness;
        atmoParams["MieBrightness"] = mieBrightness;
        atmoParams["SpotBrightness"] = spotBrightness;
        atmoParams["ScatterStrength"] = scatterStrength;
        atmoParams["RayleighStrength"] = rayleighStrength;
        atmoParams["MieStrength"] = mieStrength;
        atmoParams["RayleighCollectionPower"] = rayleighCollectionPower;
        atmoParams["MieCollectionPower"] = mieCollectionPower;
        atmoParams["MieDistribution"] = mieDistribution;
        atmoParams["LightDir"] = Vector3(0.0f,-1.0f, 0.0f);
        atmoParams["InvProj"] = procSkyCamera.projection.Inverse();
        
        cmd.Clear();
        cmd.Resize(MAX_CUBEMAP_FACES);
        for (int i = 0; i < MAX_CUBEMAP_FACES; ++i) 
        {
            cmd[i].enabled = true;
            cmd[i].blendMode = BLEND_REPLACE;
            cmd[i].tag = "ProcSky";
            cmd[i].type = CMD_QUAD;
            cmd[i].sortMode = SORT_BACKTOFRONT;
            cmd[i].pass = "postopaque";
            cmd[i].SetOutput(0, "DiffProcSky", CubeMapFace(i));
            cmd[i].vertexShaderName = "ProcSky";
            cmd[i].vertexShaderDefines = "";
            cmd[i].pixelShaderName = "ProcSky";
            cmd[i].pixelShaderDefines = "";     
            cmd[i].shaderParameters["Kr"] = atmoParams["Kr"];
            cmd[i].shaderParameters["RayleighBrightness"] = atmoParams["RayleighBrightness"];
            cmd[i].shaderParameters["MieBrightness"] = atmoParams["MieBrightness"];
            cmd[i].shaderParameters["SpotBrightness"] = atmoParams["SpotBrightness"];
            cmd[i].shaderParameters["ScatterStrength"] = atmoParams["ScatterStrength"];
            cmd[i].shaderParameters["RayleighStrength"] = atmoParams["RayleighStrength"];
            cmd[i].shaderParameters["MieStrength"] = atmoParams["MieStrength"];
            cmd[i].shaderParameters["RayleighCollectionPower"] = atmoParams["RayleighCollectionPower"];
            cmd[i].shaderParameters["MieDistribution"] = atmoParams["MieDistribution"];
            cmd[i].shaderParameters["LightDir"] = atmoParams["LightDir"];
            cmd[i].shaderParameters["InvProj"] = atmoParams["InvProj"]; 
            cmd[i].shaderParameters["InvViewRot"] = Variant(procSkyFaceRotations[i].rotationMatrix);
            
            procSkyRenderPath.AddCommand(cmd[i]);
        }
    }
    
    if (isRenderPathForLSInjected == false)
        isRenderPathForLSInjected = true;
    
    //AddRenderPathCmdForLightScattering();
}

void AddRenderPathRT(String nameRT) 
{
    RenderTargetInfo rti;
    rti.enabled = true;
    rti.filtered = true;
    rti.size = Vector2(1,1);
    rti.sizeMode = SIZE_VIEWPORTDIVISOR;
    rti.format = GetRGBAFormat();
    rti.tag = tagLS;
    rti.name = nameRT;
    procSkyRenderPath.AddRenderTarget(rti);
}

bool isRTTAlreadyExist(String nameRT) 
{
    //Array<RenderTargetInfo> rttArray = renderPath.renderTargets;
    for (int i=0; i<procSkyRenderPath.numRenderTargets ; i++) 
    {
        //RenderTargetInfo rtt = ;
        if (procSkyRenderPath.renderTargets[i].name == nameRT)
            return true;
    }
   
    return false;
}
void AddRenderPathCopyQuadCmdCopyFramebuffer() 
{
    
}

void AddRenderPathCmdForLightScattering() 
{
    if (isRenderPathForLSInjected) return;
    
    //AddRenderPathRT("SunHalo");
    //AddMRT1InPostopaquePassOutput();
    String RTTlowresRT1Name = "RTT1";
    String RTTlowresRT2Name = "RTT2";
    //AddRenderPathRT(renderPath, RTTlowresRT1Name, tagLS, Vector2(4,4));
    //AddRenderPathRT(renderPath, RTTlowresRT2Name, tagLS, Vector2(4,4));
      
    //RenderPathCommand lsCmd;
    
    //procSkyRenderPath
    isRenderPathForLSInjected = true;
}

void AddMRT1InPostopaquePassOutput()
{
    for (int i=0; i<procSkyRenderPath.numCommands-1; i++) 
    {
        RenderPathCommand cmd = procSkyRenderPath.commands[i];
        
        if (cmd.pass == "postopaque")
        {
            
            cmd.SetOutput(0, "viewport");
            cmd.SetOutput(1, "suncircle");
            //renderPath.RemoveCommand(i);
            procSkyRenderPath.commands[i] = cmd;
            //renderPath.commands[i] = cmd;
            //renderPath.commands[i].SetOutput(1, "SunHalo");
            //renderPath.InsertCommand(i, cmd);
            return;
        }   
    }    
}

bool SetRenderSize(int size) 
{
    if (size >= 1) 
    {
        procSkyCubeTexture = TextureCube();
        procSkyCubeTexture.name = "DiffProcSky";
        procSkyCubeTexture.SetSize(size, GetRGBFormat(), TEXTURE_RENDERTARGET);
        procSkyCubeTexture.filterMode = FILTER_BILINEAR;
        procSkyCubeTexture.addressMode[COORD_U] = ADDRESS_CLAMP;
        procSkyCubeTexture.addressMode[COORD_V] = ADDRESS_CLAMP;
        procSkyCubeTexture.addressMode[COORD_W] = ADDRESS_CLAMP;

        cache.AddManualResource(procSkyCubeTexture);
        if (procSkySkyBoxMaterial !is null ) 
            procSkySkyBoxMaterial.textures[TU_DIFFUSE] = procSkyCubeTexture;
        procSkyRenderSize = size;
        return true;
    }
    else 
    {
        MessageBox("ProcSky::SetSize (" + String(size) + ") ignored; requires size >= 1.");
    }
    return false;
}

void SetProcSkyAsEnvCubemapForZonesByTag(String tagZone, bool forAll = false) 
{
	Array<Node@> nodesWithZones; 
	if (!forAll)
        nodesWithZones = editorScene.GetChildrenWithTag(tagZone);
	else
        nodesWithZones = editorScene.GetChildrenWithComponent("Zone", true);
	
	if (nodesWithZones.length > 0) 
		for (int i=0; i<nodesWithZones.length; i++) 
		{
            Zone@ zone = nodesWithZones[i].GetComponent("Zone");
            if (zone !is null && procSkyCubeTexture !is null) 
            {
                zone.zoneTexture = procSkyCubeTexture;
            }
		}
}

void ProcSkyCheckKeys()
{
    if (input.keyDown[KEY_Y])
        SetProcSkyAsEnvCubemapForZonesByTag("tagProcSky", true);
}

void UpdateProcSkyCommon() 
{
    // Early out
    //if (editorScene is null || !procSkyShow) return;
    
    // Check for container and other procSky stuff (1sec delay)
    if (timeToNextProcSkyUpdate < time.systemTime) 
    {
    
		procSkyNode = editorScene.GetChild("ProcSkyContainer", true);

		if (procSkyNode is null)
		{
            isNewSceneWasOpened = true;
			procSkyNode = editorScene.CreateChild("ProcSkyContainer", LOCAL);
			procSkyNode.temporary = true;
			procSkyRenderPath = activeViewport.viewport.renderPath;
			CheckOrCreateProSkyStuff(isNewSceneWasOpened, procSkyNode.temporary);
		}
		        
        timeToNextProcSkyUpdate = time.systemTime + PROCSKY_STEP_UPDATE;
    }
    
    // Copy roration from user's node into hidded ProSkyLight node
    if (sunRotateNode !is null) 
    {
        procSkyLightNode.worldRotation = sunRotateNode.worldRotation;
    }
   
    // Render ProcSky only: first time scene load, sun orientation was changed 
    if (isNewSceneWasOpened || (procSkyLightNodeLastRotation != procSkyLightNode.worldRotation)) 
    {
		if (procSkyRenderPath !is null) 
		{
			
			SetRenderQueued(true);
        }
        
        procSkyLightNodeLastRotation = procSkyLightNode.worldRotation;
    } 
    else 
    {
		if (procSkyRenderQueued)
			SetRenderQueued(false);
    }

}

void UpdateProcSkyPerViewSplit(Camera@ camera) 
{
    // Early out
    if (camera is null || renderPath is null) return;
    
    if (editorScene is null || !procSkyShow) return;
    
    // Check if camera in ortho mode hide ProcSky
    if (camera.orthographic)
    {
        ProcSkyStuffEnabled(false);
        return;
    } 
    else 
    {
        ProcSkyStuffEnabled(true);
    }
    
    
    Vector2 sunScreen = camera.WorldToScreenPoint(sunOriginNode.worldPosition);
    sunScreen.y = 1.0 - sunScreen.y; 
    renderPath.shaderParameters["LightPositionOnScreen"] = Variant(sunScreen);

}

void UpdateViewProcSky()
{
    if (editorScene is null || !procSkyShow) return;
    
    UpdateProcSkyCommon();
    
    // Each frame update stuff
    ProcSkyCheckKeys();
    UpdateShaderParameters(procSkyRenderPath);
     
    if (isNewSceneWasOpened) isNewSceneWasOpened = false;
} 

void UpdateShaderParameters(RenderPath@ renderPath) 
{
	if (renderPath is null) return;
	
    Vector3 lightDir;
    if (procSkyLightNode !is null) 
    {
        lightDir = -procSkyLightNode.worldDirection;
        renderPath.shaderParameters["LightDir"] = Variant(lightDir);
    }
        
    renderPath.shaderParameters["Kr"] = Variant(Kr);
    renderPath.shaderParameters["RayleighBrightness"] = Variant(rayleighBrightness);
    renderPath.shaderParameters["MieBrightness"] = Variant(mieBrightness);
    renderPath.shaderParameters["SpotBrightness"] = Variant(spotBrightness);
    renderPath.shaderParameters["ScatterStrength"] = Variant(scatterStrength);
    renderPath.shaderParameters["RayleighStrength"] = Variant(rayleighStrength);
    renderPath.shaderParameters["MieStrength"] = Variant(mieStrength);
    renderPath.shaderParameters["RayleighCollectionPower"] = Variant(rayleighCollectionPower);
    renderPath.shaderParameters["MieDistribution"] = Variant(mieDistribution);
    renderPath.shaderParameters["InvProj"] = Variant(procSkyCamera.projection.Inverse());
    
}

void ProcSkyStuffEnabled(bool visible) 
{        
    if (procSkyNode !is null)
        procSkyNode.enabled = visible;
}

void SetRenderQueued(bool isQueued = true) 
{
    if (procSkyRenderQueued == isQueued || procSkyRenderPath is null) return;
    procSkyRenderPath.SetEnabled("ProcSky", isQueued);
    procSkyRenderQueued = isQueued;
    
}

void ProcSkyPostRenderUpdate()
{
    if (input.keyPress[KEY_F10] ) 
    {
        DumpTextureCube(procSkyCubeTexture, "Data/Textures/Cubemaps/ProcSky/");
    }
    
    if (!procSkyRenderQueued) return;
}

String GetTextureCubeFaceName(CubeMapFace f) 
{
    String ret = "Unknown";
    
    switch (f)
    {
        case FACE_POSITIVE_X:
            ret = "POSITIVE_X";
            break;
            
        case FACE_NEGATIVE_X:
            ret = "NEGATIVE_X";
            break;
            
        case FACE_POSITIVE_Y:
            ret = "POSITIVE_Y";
            break;
            
        case FACE_NEGATIVE_Y:
            ret = "NEGATIVE_Y";
            break;
            
        case FACE_POSITIVE_Z:
            ret = "POSITIVE_Z";
            break;
            
        case FACE_NEGATIVE_Z:
            ret = "NEGATIVE_Z";
            break;
    }
    
    return ret;
}


void DumpTextureCube(TextureCube@ texCube, String filePath) 
{
    if (texCube is null) return;
    for (int i = 0; i < MAX_CUBEMAP_FACES; i++) 
    {
        Image@ texImage = texCube.GetImage(CubeMapFace(i));
        fileSystem.CreateDir(filePath);
        String path(filePath +"ProcSkyCubemap_" + GetTextureCubeFaceName(CubeMapFace(i)) + ".png");
        if (texImage !is null) 
        {       
            texImage.SavePNG(path);
            MessageBox(path);
        }
    }
}

void HandleSkyProcHelperCheckNewNodeName(StringHash eventType, VariantMap& eventData) 
{
    Node@ node = eventData["Node"].GetPtr();
    if (node !is null)
    {
        // Try to find user's node for rotation sun (node for copy rotation)
		if (sunRotateNode is null && node.name == "Sun")
		{
            sunRotateNode = node;
		}
    }
}

void HandleSkyProcHelperNodeRemoved(StringHash eventType, VariantMap& eventData) 
{
    Node@ node = eventData["Node"].GetPtr();
    
    if (node !is null) 
    {
		if (sunRotateNode is node) 
		{
            sunRotateNode = null;
		}
    }

}