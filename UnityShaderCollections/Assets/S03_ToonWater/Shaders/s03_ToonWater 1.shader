Shader "Jack/ToonWater"
{
    Properties
    {
    	[Header(water color)]
		//  color in the shallow area
		_DepthGradientShallow("Shallow Color", Color) = (0.325, 0.807, 0.971, 0.725)
		_DepthGradientDeep("Deep Color", Color) = (0.086, 0.407, 1, 0.749)
		_DepthMaxDistance("Depth Max Dis", Float) = 1
		
		// waves texture
    	[Header(water noise)]
		_SurfaceNoise("surface Noise", 2D) = "white" {}
		
        _SurfaceDistortion("Surface Distortion", 2D) = "white" {}	
		_SurfaceDistortionAmount("Surface Distortion Amount", Range(0, 1)) = 0.27
        _SurfaceNoiseCutoff("Surface Noise Cutoff", Range(0, 1)) = 0.777
    	
    	[Header(water animation)]
    	_SurfaceNoiseScroll("water flow (x,y)", Vector) = (0.03, 0.03, 0, 0)
    	
        [Header(water foam)]
	    // foam color
		_FoamColor("Foam Color", Color) = (1,1,1,1)
		_FoamDistance("Foam amount", Range(0,1)) = 0.5

    }
    SubShader
    {
		Tags
		{
			"Queue" = "Transparent"
		}

        Pass
        {
	        Blend SrcAlpha OneMinusSrcAlpha
			ZWrite Off

            CGPROGRAM
			#define SMOOTHSTEP_AA 0.01

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

			// Blends alpha, (1- alpha)
			float4 alphaBlend(float4 top, float4 bottom)
			{
				float3 color = (top.rgb * top.a) + (bottom.rgb * (1 - top.a));
				float alpha = top.a + bottom.a * (1 - top.a);

				return float4(color, alpha);
			}

            struct appdata
            {
                float4 vertex : POSITION;
				float4 uv     : TEXCOORD0;
				float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 pos            : SV_POSITION;	
				float2 noiseUV        : TEXCOORD0;
				float2 distortUV      : TEXCOORD1;
				float4 screenPosition : TEXCOORD2;
				float3 viewNormal     : NORMAL;
            };

			sampler2D _SurfaceNoise;       float4 _SurfaceNoise_ST;
			sampler2D _SurfaceDistortion;  float4 _SurfaceDistortion_ST;
			sampler2D _CameraDepthTexture;
            float4 _DepthGradientShallow;
			float4 _DepthGradientDeep;
			float4 _FoamColor;
			float _DepthMaxDistance;
			float _FoamMaxDistance;
			float _FoamMinDistance;
			float _SurfaceNoiseCutoff;
			float _SurfaceDistortionAmount;
			float2 _SurfaceNoiseScroll;
			float _FoamDistance;



            
            v2f vert (appdata v)
            {
                v2f o;
                o.pos         = UnityObjectToClipPos(v.vertex);
				o.screenPosition = ComputeScreenPos(o.pos);			// 
				o.distortUV      = TRANSFORM_TEX(v.uv, _SurfaceDistortion);
				o.noiseUV        = TRANSFORM_TEX(v.uv, _SurfaceNoise);
				o.viewNormal     = COMPUTE_VIEW_NORMAL;
                return o;
            }
            
            float4 frag (v2f i) : SV_Target
            {
				// 1. convert pixel depth to color
	           	float existingDepth01 = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, i.pos.xy/_ScreenParams.xy);
				float existingDepthLinear = LinearEyeDepth(existingDepth01);
				float depthDifference = existingDepthLinear - i.screenPosition.w;  // depth - surface depth
				float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);  // convert to [0,1]
				float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01); // convert to color
				
				// 2. noise texture
            	// get distort intensity, change from [0,1] to [-1,1] * distortionAmount
				float2 distortSample = (tex2D(_SurfaceDistortion, i.distortUV).xy * 2 - 1) * _SurfaceDistortionAmount;
            	// uv0 + distortion + velocity
				float2 noiseUV = float2(i.noiseUV.x + distortSample.x + _Time.x * _SurfaceNoiseScroll.x , 
				  i.noiseUV.y + distortSample.y + _Time.x * _SurfaceNoiseScroll.y );
            	float surfaceNoiseSample = tex2D(_SurfaceNoise, noiseUV).r;
				float surfaceNoiseCutoff =  _SurfaceNoiseCutoff * saturate(depthDifference/_FoamDistance) ;
            	float surfaceNoise = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);

            	// foam color
				float4 surfaceNoiseColor = _FoamColor;
            	// blend
				surfaceNoiseColor.a *= surfaceNoise;
				return alphaBlend(surfaceNoiseColor, waterColor);
            }
            ENDCG
        }
    }
}
