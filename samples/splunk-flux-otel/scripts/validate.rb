#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'fileutils'
require 'open3'
Dir.chdir(File.expand_path('..',__dir__))
FileUtils.mkdir_p('.cache/rendered')
charts={'haproxy'=>'haproxy.tgz','splunk'=>'splunk.tgz','keda'=>'keda.tgz','agent'=>'agent.tgz','otel-scaler'=>'otel-add-on-0.1.5.tgz','predictor'=>'kedify-predictor-0.1.9.tgz'}
charts.each do |component,archive|
  release=YAML.load_file("infrastructure/#{component}/release.yaml")
  spec=release['spec']; values=Marshal.load(Marshal.dump(spec['values']))
  if component=='splunk'
    if values['splunkPlatform']
      values['splunkPlatform']['endpoint']='https://validation.example/services/collector/event'
    else
      values['splunkObservability']['realm']='us0'
    end
  end
  File.write(".cache/#{component}-values.yaml",YAML.dump(values))
  chart=".cache/charts/#{archive}"
  abort "Missing #{chart}; download the pinned charts first (see README)" unless File.exist?(chart)
  out,err,status=Open3.capture3('helm','template',spec['releaseName'],chart,'--namespace',spec['targetNamespace'],'--values',".cache/#{component}-values.yaml",'--kube-version','1.35.0',*(component=='splunk' ? ['--skip-schema-validation'] : []))
  abort err unless status.success?
  File.write(".cache/rendered/#{component}.yaml",out)
  docs=YAML.load_stream(out).compact
  if component=='splunk'
    cm=docs.find {|d|d['kind']=='ConfigMap' && d.dig('data','relay')&.include?('metrics/scaling')}
    abort 'Scaling pipeline not rendered' unless cm
    config=YAML.safe_load(cm['data']['relay'])
    File.write('.cache/rendered/splunk-collector.yaml',YAML.dump(config))
    pipelines=config.dig('service','pipelines')
    abort 'Original monitoring pipeline removed' unless pipelines['metrics']['exporters'].include?(values['splunkPlatform'] ? 'splunk_hec/platform_metrics' : 'signalfx')
    abort 'Scaling exporter missing' unless pipelines['metrics/scaling']['exporters']==['otlp/scaling']
    sa=docs.find {|d|d['kind']=='Deployment' && d.dig('metadata','name').end_with?('k8s-cluster-receiver')}
    puts "Splunk collector SA: #{sa&.dig('spec','template','spec','serviceAccountName')}"
  end
  puts "Rendered #{component}: #{docs.size} resources"
end
Dir.glob('{apps,infrastructure}/**/kustomization.yaml').each do |file|
  out,status=Open3.capture2e('kubectl','kustomize',File.dirname(file));abort out unless status.success?
end
so=YAML.load_file('apps/scaling/scaledobject.yaml')
abort 'Predictor must not drive scaling' unless so.dig('spec','triggers').all? {|t| t['type']=='external' && t.dig('metadata','scalerAddress').start_with?('otel-scaler.')}
abort 'Flux must not own replicas' if YAML.load_stream(File.read('apps/nginx/workload.yaml')).any? {|d| d['kind']=='Deployment' && d['spec'].key?('replicas')}
out,status=Open3.capture2e('kubectl','kustomize','clusters/mobility-global');abort out unless status.success?
repo_root=File.expand_path('../..',Dir.pwd)
flux_docs=YAML.load_stream(File.read('clusters/mobility-global/reconciliation.yaml')) + YAML.load_stream(File.read('clusters/mobility-global/flux-system/gotk-sync.yaml'))
flux_docs.compact.select {|d|d['kind']=='Kustomization'}.each do |doc|
  path=doc.dig('spec','path')
  target=File.expand_path(path,repo_root)
  abort "Flux path escapes this example: #{path}" unless target.start_with?(Dir.pwd+'/')
  abort "Flux path has no kustomization.yaml: #{path}" unless File.file?(File.join(target,'kustomization.yaml'))
end
puts 'All Kustomizations build; repository-relative Flux paths resolve; scaling remains independent of Predictor.'
