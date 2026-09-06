// Reflection-only bridge compiled with Windows csc and hosted by verified .NET 8.
// Reads copied Unity bundles together; clears renderer references in memory only.
// rig.json retains source local TRS; AssetStudio FBX conversion changes handedness.
using System;
using System.Reflection;
using System.IO;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
class Export
{
    static string dir;
    static Assembly core,utility,fbx;
    static object F(object o,string n)
    {
        return o.GetType().GetField(n).GetValue(o);
    }
    static void S(object o,string n,object v)
    {
        o.GetType().GetField(n).SetValue(o,v);
    }
    static object Ptr(object p)
    {
        foreach(var m in p.GetType().GetMethods())
        {
            if(m.Name=="TryGet"&&!m.IsGenericMethod&&m.GetParameters().Length==1)
            {
                object[] a=
                {
                    null
                }
                ;
                return (bool)m.Invoke(p,a)?a[0]:null;
            }
        }
        return null;
    }
    static string Q(string s)
    {
        return "\""+s.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\r","\\r").Replace("\n","\\n")+"\"";
    }
    static string N(object v)
    {
        return Convert.ToString(v,CultureInfo.InvariantCulture);
    }
    static string V(object v,bool quat)
    {
        string s="["+N(F(v,"X"))+","+N(F(v,"Y"))+","+N(F(v,"Z"));
        return s+(quat?","+N(F(v,"W")):"")+"]";
    }
    static void Main(string[] args)
    {
        dir=args[2];
        AppDomain.CurrentDomain.AssemblyResolve+=(s,e)=>
        {
            string p=Path.Combine(dir,new AssemblyName(e.Name).Name+".dll");
            return File.Exists(p)?Assembly.LoadFrom(p):null;
        }
        ;
        try
        {
            Run(args);
        }
        catch(Exception e)
        {
            Console.WriteLine(e);
            Environment.ExitCode=1;
        }
    }
    static void Run(string[] args)
    {
        core=Assembly.LoadFrom(Path.Combine(dir,"AssetStudio.dll"));
        utility=Assembly.LoadFrom(Path.Combine(dir,"AssetStudio.Utility.dll"));
        fbx=Assembly.LoadFrom(Path.Combine(dir,"AssetStudio.FBXWrapper.dll"));
        var game=core.GetType("AssetStudio.GameManager").GetMethod("GetGame",new[]
        {
            typeof(string)
        }
        ).Invoke(null,new object[]
        {
            "Normal"
        }
        );
        var manager=Activator.CreateInstance(core.GetType("AssetStudio.AssetsManager"));
        S(manager,"Game",game);
        S(manager,"ResolveDependencies",false);
        manager.GetType().GetMethod("LoadFiles").Invoke(manager,new object[]
        {
            Directory.GetFiles(args[0])
        }
        );
        Directory.CreateDirectory(args[1]);
        var animators=new List<object>();
        var clips=new List<object>();
        var transforms=new List<string>();
        var avatars=new List<string>();
        foreach(var file in (IEnumerable)F(manager,"assetsFileList"))
        {
            foreach(var o in (IEnumerable)F(file,"Objects"))
            {
                string type=o.GetType().Name;
                if(type=="GameObject")
                {
                    S(o,"m_MeshRenderer",null);
                    S(o,"m_SkinnedMeshRenderer",null);
                }
                if(type=="Animator")animators.Add(o);
                if(type=="AnimationClip")clips.Add(o);
                if(type=="Avatar")
                {
                    var map=(IDictionary)F(o,"m_TOS");
                    var rows=new List<string>();
                    foreach(DictionaryEntry kv in map)rows.Add(Q(N(kv.Key))+":"+Q((string)kv.Value));
                    avatars.Add("{\"name\":"+Q((string)F(o,"m_Name"))+",\"paths\":{"+string.Join(",",rows)+"}}");
                }
                if(type=="Transform")
                {
                    var go=Ptr(F(o,"m_GameObject"));
                    var father=Ptr(F(o,"m_Father"));
                    transforms.Add("{\"id\":"+Q(N(F(o,"m_PathID")))+",\"name\":"+Q(go==null?"?":(string)F(go,"m_Name"))+",\"parent\":"+(father==null?"null":Q(N(F(father,"m_PathID"))))+",\"translation\":"+V(F(o,"m_LocalPosition"),false)+",\"rotation\":"+V(F(o,"m_LocalRotation"),true)+",\"scale\":"+V(F(o,"m_LocalScale"),false)+"}");
                }
            }
        }
        File.WriteAllText(Path.Combine(args[1],"rig.json"),"{\"coordinate_system\":\"Unity source local TRS; no basis conversion\",\"transforms\":["+string.Join(",",transforms)+"],\"avatars\":["+string.Join(",",avatars)+"]}");
        Console.WriteLine("Loaded animators="+animators.Count+" clips="+clips.Count+" transforms="+transforms.Count);
        if(animators.Count!=1||clips.Count==0)throw new Exception("Expected one rig animator and >=1 clips");
        var options=Activator.CreateInstance(utility.GetType("AssetStudio.ModelConverter+Options"));
        S(options,"game",game);
        S(options,"collectAnimations",false);
        S(options,"exportMaterials",false);
        var eo=Activator.CreateInstance(fbx.GetType("AssetStudio.Fbx+ExportOptions"));
        S(eo,"exportAllNodes",true);
        S(eo,"exportSkins",false);
        S(eo,"exportAnimations",true);
        S(eo,"exportBlendShape",false);
        S(eo,"eulerFilter",false);
        S(eo,"scaleFactor",1f);
        S(eo,"boneSize",10);
        S(eo,"fbxVersion",3);
        S(eo,"fbxFormat",0);
        foreach(var clip in clips)
        {
            var ca=Array.CreateInstance(core.GetType("AssetStudio.AnimationClip"),1);
            ca.SetValue(clip,0);
            var converter=Activator.CreateInstance(utility.GetType("AssetStudio.ModelConverter"),new object[]
            {
                animators[0],options,ca
            }
            );
            string name=(string)F(clip,"m_Name");
            string path=Path.Combine(args[1],name+".fbx");
            utility.GetType("AssetStudio.ModelExporter").GetMethod("ExportFbx").Invoke(null,new[]
            {
                (object)path,converter,eo
            }
            );
            Console.WriteLine("EXPORTED "+name+" "+new FileInfo(path).Length);
        }
    }
}
