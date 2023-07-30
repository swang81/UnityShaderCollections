// version 1.0  230720
// this is a simple surface shader demo

Shader "Jack/MyPBR"
{
	Properties
	{
		_Color("Color",color) = (1,1,1,1)	                 //main color
		_MainTex("Albedo",2D) = "white"{}	                 //Albedo
		_MetallicGlossMap("Metallic",2D) = "white"{}         //RA Map, R: metallic，A: Smoothness
		_BumpMap("Normal Map",2D) = "bump"{}                 //Normal Map
		_OcclusionMap("Occlusion",2D) = "white"{}            //AO Map
		_MetallicStrength("MetallicStrength",Range(0,1)) = 1 //Metallic strength
		_GlossStrength("Smoothness",Range(0,1)) = 0.5        //Smoothness
		_BumpScale("Normal Scale",float) = 1                 //Normal strength
		_EmissionColor("Color",color) = (0,0,0)            //Emission Color
		_EmissionMap("Emission Map",2D) = "white"{}          //Emission Map
	}
	
	CGINCLUDE
		#include "UnityCG.cginc"
		#include "Lighting.cginc"
		#include "AutoLight.cginc"
		// ambient or light map uv
		inline half4 VertexGI(float2 uv1,float2 uv2,float3 worldPos,float3 worldNormal)
		{
			half4 ambientOrLightmapUV = 0;

			//
			#ifdef LIGHTMAP_ON
				ambientOrLightmapUV.xy = uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
				// non-static object, lighting sample 
			#elif UNITY_SHOULD_SAMPLE_SH
				// non-important vertex lighting
				#ifdef VERTEXLIGHT_ON
					// calculate 4 vertex lighting 
					ambientOrLightmapUV.rgb = Shade4PointLights(
						unity_4LightPosX0,unity_4LightPosY0,unity_4LightPosZ0,
						unity_LightColor[0].rgb,unity_LightColor[1].rgb,unity_LightColor[2].rgb,unity_LightColor[3].rgb,
						unity_4LightAtten0,worldPos,worldNormal);
				#endif
				//calculate sh lighting
				ambientOrLightmapUV.rgb += ShadeSH9(half4(worldNormal,1));
			#endif

			// dynamiclightmap uv
			#ifdef DYNAMICLIGHTMAP_ON
				ambientOrLightmapUV.zw = uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
			#endif

			return ambientOrLightmapUV;
		}
	
		//indirect diffuse
		inline half3 ComputeIndirectDiffuse(half4 ambientOrLightmapUV,half occlusion)
		{
			half3 indirectDiffuse = 0;

			//如果是动态物体，间接光漫反射为在顶点函数中计算的非重要光源
			#if UNITY_SHOULD_SAMPLE_SH
				indirectDiffuse = ambientOrLightmapUV.rgb;	
			#endif

			//对于静态物体，则采样光照贴图或动态光照贴图
			#ifdef LIGHTMAP_ON
				//对光照贴图进行采样和解码
				//UNITY_SAMPLE_TEX2D定义在HLSLSupport.cginc
				//DecodeLightmap定义在UnityCG.cginc
				indirectDiffuse = DecodeLightmap(UNITY_SAMPLE_TEX2D(unity_Lightmap,ambientOrLightmapUV.xy));
			#endif
		
			#ifdef DYNAMICLIGHTMAP_ON
				//对动态光照贴图进行采样和解码
				//DecodeRealtimeLightmap定义在UnityCG.cginc
				indirectDiffuse += DecodeRealtimeLightmap(UNITY_SAMPLE_TEX2D(unity_DynamicLightmap,ambientOrLightmapUV.zw));
			#endif

			//将间接光漫反射乘以环境光遮罩，返回
			return indirectDiffuse * occlusion;
		}
	
		inline half3 BoxProjectedDirection(half3 worldRefDir,float3 worldPos,float4 cubemapCenter,float4 boxMin,float4 boxMax)
		{
			//使下面的if语句产生分支，定义在HLSLSupport.cginc中
			UNITY_BRANCH
			if(cubemapCenter.w > 0.0)//如果反射探头开启了BoxProjection选项，cubemapCenter.w > 0
			{
				half3 rbmax = (boxMax.xyz - worldPos) / worldRefDir;
				half3 rbmin = (boxMin.xyz - worldPos) / worldRefDir;

				half3 rbminmax = (worldRefDir > 0.0f) ? rbmax : rbmin;

				half fa = min(min(rbminmax.x,rbminmax.y),rbminmax.z);

				worldPos -= cubemapCenter.xyz;
				worldRefDir = worldPos + worldRefDir * fa;
			}
			return worldRefDir;
		}
		//Sampler probe
		inline half3 SamplerReflectProbe(UNITY_ARGS_TEXCUBE(tex),half3 refDir,half roughness,half4 hdr)
		{
			roughness = roughness * (1.7 - 0.7 * roughness);
			half mip = roughness * 6;
			//对反射探头进行采样
			//UNITY_SAMPLE_TEXCUBE_LOD定义在HLSLSupport.cginc，用来区别平台
			half4 rgbm = UNITY_SAMPLE_TEXCUBE_LOD(tex,refDir,mip);
			//采样后的结果包含HDR,所以我们需要将结果转换到RGB
			//定义在UnityCG.cginc
			return DecodeHDR(rgbm,hdr);
		}
	
		//indirect specular
		inline half3 ComputeIndirectSpecular(half3 refDir,float3 worldPos,half roughness,half occlusion)
		{
			half3 specular = 0;
			// resample 1st sample probe
			half3 refDir1 = BoxProjectedDirection(refDir,worldPos,unity_SpecCube0_ProbePosition,unity_SpecCube0_BoxMin,unity_SpecCube0_BoxMax);
			//sample 1st reflect probe
			half3 ref1 = SamplerReflectProbe(UNITY_PASS_TEXCUBE(unity_SpecCube0),refDir1,roughness,unity_SpecCube0_HDR);
			// if/ else defined in HLSLSupport.cginc. if probe 1 weight < 1.0, mix the probe 2
			UNITY_BRANCH
			if(unity_SpecCube0_BoxMin.w < 0.99999)
			{
				//second sampler probe reflection direction
				half3 refDir2 = BoxProjectedDirection(refDir,worldPos,unity_SpecCube1_ProbePosition,unity_SpecCube1_BoxMin,unity_SpecCube1_BoxMax);
				//resample second reflect probe 
				half3 ref2 = SamplerReflectProbe(UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1,unity_SpecCube0),refDir2,roughness,unity_SpecCube1_HDR);
				//mix them
				specular = lerp(ref2,ref1,unity_SpecCube0_BoxMin.w);
			}
			else
			{
				specular = ref1;
			}
			return specular * occlusion;
		}
		//V is Smith-Joint shadowing-masking function
		inline half ComputeSmithJointGGXVisibilityTerm(half nl,half nv,half roughness)
		{
			half ag = roughness * roughness;
			half lambdaV = nl * (nv * (1 - ag) + ag);
			half lambdaL = nv * (nl * (1 - ag) + ag);
			return 0.5f/(lambdaV + lambdaL + 1e-5f);
		}
		// D is normal distributed function
		inline half ComputeGGXTerm(half nh,half roughness)
		{
			half a = roughness * roughness;
			half a2 = a * a;
			half d = (a2 - 1.0f) * nh * nh + 1.0f;
			//UNITY_INV_PI is 1/π
			return a2 * UNITY_INV_PI / (d * d + 1e-5f);
		}
		// F is fresnel function
		inline half3 ComputeFresnelTerm(half3 F0,half cosA)
		{
			return F0 + (1 - F0) * pow(1 - cosA, 5);
		}
	
		// Disney diffuse term 
		inline half3 ComputeDisneyDiffuseTerm(half nv,half nl,half lh,half roughness,half3 baseColor)
		{
			half Fd90 = 0.5f + 2 * roughness * lh * lh;
			return baseColor * UNITY_INV_PI * (1 + (Fd90 - 1) * pow(1-nl,5)) * (1 + (Fd90 - 1) * pow(1-nv,5));
		}
	
		//计算间接光镜面反射菲涅尔项
		inline half3 ComputeFresnelLerp(half3 c0,half3 c1,half cosA)
		{
			half t = pow(1 - cosA,5);
			return lerp(c0,c1,t);
		}
	ENDCG
	
	SubShader
	{
		Tags{"RenderType" = "Opaque"}
		pass
		{
			Tags{"LightMode" = "ForwardBase"}
			CGPROGRAM
			#pragma target 3.0
			#pragma multi_compile_fwdbase
			#pragma multi_compile_fog
			#pragma vertex vert
			#pragma fragment frag
			
			half4 _Color;
			sampler2D _MainTex;
			float4 _MainTex_ST;
			sampler2D _MetallicGlossMap;
			sampler2D _BumpMap;
			sampler2D _OcclusionMap;
			half _MetallicStrength;
			half _GlossStrength;
			float _BumpScale;
			half4 _EmissionColor;
			sampler2D _EmissionMap;

			struct a2v
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 tangent :TANGENT;
				float2 texcoord : TEXCOORD0;
				float2 texcoord1 : TEXCOORD1;  // lightmap uv
				float2 texcoord2 : TEXCOORD2;  // dynamicLightMap uv
			};
			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				half4 ambientOrLightmapUV : TEXCOORD1; // ambient or lightmap uv
				float4 TtoW0 : TEXCOORD2;
				float4 TtoW1 : TEXCOORD3;
				float4 TtoW2 : TEXCOORD4; //xyz from tangent to world
				SHADOW_COORDS(5)          // shadow variables  in AutoLight.cginc
				UNITY_FOG_COORDS(6)       // fog variables in UnityCG.cginc
			};
			
			v2f vert(a2v v)
			{
				v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f,o);   // initialize
				
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord,_MainTex); 

				float3 worldPos     = mul(unity_ObjectToWorld,v.vertex);
				half3 worldNormal   = UnityObjectToWorldNormal(v.normal);
				half3 worldTangent  = UnityObjectToWorldDir(v.tangent);
				half3 worldBinormal = cross(worldNormal,worldTangent) * v.tangent.w;

				//compute ambient or lightmap uv
				o.ambientOrLightmapUV = VertexGI(v.texcoord1,v.texcoord2,worldPos,worldNormal);

				// matrix 3x3 from tangent to world space, 3x1 is world pos
				o.TtoW0 = float4(worldTangent.x,worldBinormal.x,worldNormal.x,worldPos.x);
				o.TtoW1 = float4(worldTangent.y,worldBinormal.y,worldNormal.y,worldPos.y);
				o.TtoW2 = float4(worldTangent.z,worldBinormal.z,worldNormal.z,worldPos.z);

				//Shadow parameters in AutoLight.cginc
				TRANSFER_SHADOW(o);
				//Fog parameters in UnityCG.cginc
				UNITY_TRANSFER_FOG(o,o.pos);
				return o;
			}

			half4 frag(v2f i) : SV_Target
			{
				//data
				float3 worldPos     = float3(i.TtoW0.w,i.TtoW1.w,i.TtoW2.w); // world pos
				half3  albedo       = tex2D(_MainTex,i.uv).rgb * _Color.rgb;               // albedo
				half metallic       = tex2D(_MetallicGlossMap,i.uv).r * _MetallicStrength; // metallic
				half roughness      = 1 - tex2D(_MetallicGlossMap,i.uv).a * _GlossStrength;// ranghness
				half occlusion      = tex2D(_OcclusionMap,i.uv).g;                         // AO

				//normal in world space
				half3 normalTangent = UnpackNormal(tex2D(_BumpMap,i.uv));
				normalTangent.xy *= _BumpScale;
				normalTangent.z = sqrt(1.0 - saturate(dot(normalTangent.xy,normalTangent.xy)));
				half3 worldNormal = normalize(half3(dot(i.TtoW0.xyz,normalTangent),
									dot(i.TtoW1.xyz,normalTangent),dot(i.TtoW2.xyz,normalTangent)));

				half3 lightDir = normalize(UnityWorldSpaceLightDir(worldPos)); //light Dir in WS
				half3 viewDir  = normalize(UnityWorldSpaceViewDir(worldPos));  //view Dir in WS
				half3 refDir   = reflect(-viewDir,worldNormal);                //view reflect Dir in WS
				half3 emission = tex2D(_EmissionMap,i.uv).rgb * _EmissionColor;//Emission color

				UNITY_LIGHT_ATTENUATION(atten,i,worldPos);  //compute shadow and attenuation

				//calculate BRDF parameters
				half3 halfDir = normalize(lightDir + viewDir);
				half nv       = saturate(dot(worldNormal,viewDir));
				half nl       = saturate(dot(worldNormal,lightDir));
				half nh       = saturate(dot(worldNormal,halfDir));
				half lv       = saturate(dot(lightDir,viewDir));
				half lh       = saturate(dot(lightDir,halfDir));

				//specular color     metallic ->1,   it tends to be albedo
				//                 non-metallic->0,  it tends to be (0.04, 0.04, 0.04)
				half3 specColor = lerp(unity_ColorSpaceDielectricSpec.rgb, albedo, metallic);
				
				//compute kd - diffusion
				half oneMinusReflectivity = (1 - metallic) * unity_ColorSpaceDielectricSpec.a; // kd
				half3 diffColor = albedo * oneMinusReflectivity;  

				//compute indirect
				half3 indirectDiffuse  = ComputeIndirectDiffuse(i.ambientOrLightmapUV,occlusion);      // indirect diffuse
				half3 indirectSpecular = ComputeIndirectSpecular(refDir,worldPos,roughness,occlusion);// indirect specular

				//计算掠射角时反射率
				half grazingTerm = saturate((1 - roughness) + (1-oneMinusReflectivity));

				//计算间接光镜面反射
				indirectSpecular *= ComputeFresnelLerp(specColor,grazingTerm,nv);
				//计算间接光漫反射
				indirectDiffuse *= diffColor;

				// direct light
				half  V = ComputeSmithJointGGXVisibilityTerm(nl,nv,roughness);// BRDF Specular V term
				half  D = ComputeGGXTerm(nh,roughness);						  // BRDF Specular D term
				half3 F = ComputeFresnelTerm(specColor,lh);					  // BRDR Specular F term 

				half3 specularTerm = V * D * F;                                             // specular term
				half3 diffuseTerm = ComputeDisneyDiffuseTerm(nv,nl,lh,roughness,diffColor); // diffuse term
				
				//final RGB
				half3 color = UNITY_PI * (diffuseTerm + specularTerm) * _LightColor0.rgb * nl * atten  // direct light 
								+ indirectDiffuse + indirectSpecular + emission;				// indirect light
				
				//fog effect
				UNITY_APPLY_FOG(i.fogCoord, color.rgb);
				return half4(color,1);
			}

			ENDCG
		}
	}
	FallBack "VertexLit"
}
