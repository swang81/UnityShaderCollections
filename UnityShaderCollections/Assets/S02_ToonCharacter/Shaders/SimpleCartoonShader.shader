Shader "Jack/simpleCartoon"
{
    Properties
    {
        _BaseMap ("Texture", 2D) = "white" {}
        _SSSMap("Texture", 2D) = "black" {}
        _ILMMap("ILMMap",2D)= "white" {}
        _DetailMap("detailMap",2D)= "white" {}
        _ToonThreshold("toonThreshold", Range(0,1)) =0.5
        _ToonHardness("toonHardness", float) = 20.0
        _SpecSize("specSize",Range(0,1)) = 0.15
        _RimLightDir("RimLight Dir", Vector) = (1, 0, -1, 0)
        _RimLightColor("RimLight Color", Color) = (1,1,1,1)
        _SpecColor("specColor",Color) = (1,1,1,1)
        _OutlineWidth("Outline",float) = 7.0
        _OutLineColor("OutlineColor",Color) = (1,1,1,1)
        _OutlineZbias("OutlineZbias", float) = -10
    }
    SubShader
    {
        Tags { "LightMode" = "ForwardBase"  }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase 
            #include "AutoLight.cginc"
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 texcoord0 : TEXCOORD0;
                float2 texcoord1 : TEXCOORD1;
                float3 normal :NORMAL;
                float4 color: COLOR;
            };

            struct v2f
            {
                float4 uv : TEXCOORD0;
                
                float4 pos : SV_POSITION;
                float3 pos_world: TEXCOORD1;
                float3 normal_world: TEXCOORD2;
                float4 vertex_color: TEXCOORD3;
            };

            sampler2D _BaseMap;
            sampler2D _SSSMap;
            sampler2D _ILMMap;
            sampler2D _DetailMap;
            float _ToonThreshold;
            float _ToonHardness;
            float _SpecSize;
            float4 _SpecColor;
            float4 _RimLightDir;
            float4 _RimLightColor;

            
            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.pos_world = mul(unity_ObjectToWorld,v.vertex).xyz;
                o.normal_world = UnityObjectToWorldNormal(v.normal);
                o.uv = float4(v.texcoord0, v.texcoord1);
                o.vertex_color = v.color;
                return o;
            }

            half4 frag(v2f i):SV_Target
            {
                
                half2 uv1 = i.uv.xy;
                half2 uv2 = i.uv.zw;
                //
                float3 normalDir = normalize(i.normal_world);
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.pos_world);
                
                half4 base_map = tex2D(_BaseMap, uv1);
                half3 base_color = base_map.rgb;
                half4 sss_map = tex2D(_SSSMap, uv1);
                half3 sss_color = sss_map.rgb;

                // ilm map
                half4 ilm_map = tex2D(_ILMMap,uv1);
                float spec_intensity = ilm_map.r;
                float diffuse_control = ilm_map.g *2.0 - 1.0; // shift light
                float spec_size = ilm_map.b;
                float inner_line = ilm_map.a;
                // vertex color
                float ao = i.vertex_color.r;
                

                // diffse
                half NdotL = dot(normalDir, lightDir);
                half half_lambert = (NdotL +1.0) *0.5;
                half lambert_term = half_lambert * ao + diffuse_control;
                half toon_diffuse = saturate((lambert_term - _ToonThreshold )* _ToonHardness);
                half3 final_diffuse = lerp(sss_color, base_color, toon_diffuse);
                
                // specular
                float NdotV = (dot(normalDir, viewDir) + 1.0) * 0.5; 
                float spec_term = NdotV * ao + diffuse_control;
                spec_term = half_lambert * 0.9 + spec_term * 0.1;
                half toon_spec = saturate((spec_term - (1.0- spec_size * _SpecSize) )* 500);
                half3 spec_color = (_SpecColor.xyz + base_color)*0.5;
                half3 final_spec = toon_spec* spec_color * spec_intensity;
                
                // draw inner line
                half3 inner_line_color = lerp(base_color*0.2, float3(1.0,1.0,1.0), inner_line);
                half3 detail_color = tex2D(_DetailMap,uv2);
                detail_color = lerp(base_color*0.2, float3(1.0,1.0,1.0),  detail_color );
                half3 final_line = inner_line_color * inner_line_color * detail_color;
                
                // add light, rim light,
                // float3 lightDir_rim = normalize(_RimLightColor.xyz);
                // half NdotL_rim = (dot(normalDir, lightDir_rim)+1.0) * 0.5;
                // half rimLight_term =  NdotL_rim + diffuse_control;
                // //half3 final_rimlight = 
                
                //
                half3 final_color = (final_diffuse + final_spec) * final_line;
                final_color = sqrt(max(exp2(log2(max(final_color,0.0))*2.2),0.0));                
                return float4(final_color,1);
            }
            ENDCG
        }
        
        
        // draw outline
        Pass
        {
            Cull Front
            
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase 
            #include "AutoLight.cginc"
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 texcoord0 : TEXCOORD0;
                float3 normal :NORMAL;
                float4 color: COLOR;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 pos : SV_POSITION;
                float4 vertex_color: TEXCOORD3;
            };

            sampler2D _BaseMap;
            sampler2D _SSSMap;
            sampler2D _ILMMap;
            float _OutlineWidth;
            float4 _OutLineColor;
            float _OutlineZbias;
            
            v2f vert (appdata v)
            {
                v2f o;
                float3 pos_view = UnityObjectToViewPos(v.vertex);
                float3 outline_dir = mul((float3x3)UNITY_MATRIX_IT_MV, v.normal); //normal view direction
                outline_dir.z = _OutlineZbias * (1.0 - v.color.b);
                outline_dir = normalize(outline_dir);
                pos_view+= outline_dir * _OutlineWidth * 0.001 * v.vertex.a;

                o.pos = mul(UNITY_MATRIX_P, float4(pos_view,1.0));
                o.uv = v.texcoord0;
                o.vertex_color = v.color;
                return o; 
            }

            half4 frag(v2f i): SV_Target
            {
                // change linecolor to high color
                float3 basecolor = tex2D(_BaseMap, i.uv.xy).xyz;
                half maxComponent = max(max(basecolor.r, basecolor.g),basecolor.b) - 0.004;
                half3 saturateColor = step(maxComponent.rrr, basecolor) * basecolor;
                saturateColor = lerp(basecolor.rgb, saturateColor, 0.6);
                half3 outlineColor = 0.8 * saturateColor * basecolor * _OutLineColor.xyz;
                return float4(outlineColor, 1.0);
            }
            ENDCG
        }
    }
}
