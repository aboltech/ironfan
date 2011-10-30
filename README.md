# cluster_chef

Chef is a powerful tool for maintaining and describing the software and configurations that let a machine provide its services.

cluster_chef is

* a clean, expressive way to describe how machines and roles are assembled into a working cluster.
* Our collection of Industrial-strength, cloud-ready recipes for Hadoop, Cassandra, HBase, Elasticsearch and more.
* a set of conventions and helpers that make provisioning cloud machines easier.

## Walkthrough

Here's a very simple cluster:


```ruby
ClusterChef.cluster 'awesome' do
  cloud(:ec2) do
    flavor              't1.micro'
  end

  role                  :base_role
  role                  :chef_client
  role                  :ssh

  # The database server
  facet :dbnode do
    instances           1
    role                :mysql_server

    cloud do
      flavor           'm1.large'
      backing          'ebs'
    end
  end

  # A throwaway facet for development.
  facet :webnode do
    instances           2
    role                :nginx_server
    role                :awesome_webapp
  end
end
```

This code defines a cluster named demosimple. A cluster is a group of servers united around a common purpose, in this case to serve a scalable web application.

The awesome cluster has two 'facets' -- dbnode and webnode. A facet is a subgroup of interchangeable servers that provide a logical set of systems: in this case, the systems that store the website's data and those that render it.

The dbnode facet has one server, which will be named 'awesome-dbnode-0'; the webnode facet has two servers, 'awesome-webnode-0' and 'awesome-webnode-1'.

Each server inherits the appropriate behaviors from its facet and cluster. All the servers in this cluster have the `base_role`, `chef_client` and `ssh` roles. The dbnode machines additionally house a MySQL server, while the webnodes have an nginx reverse proxy for the custom `awesome_webapp`.

As you can see, the dbnode facet asks for a different flavor of machine ('m1.large') than the cluster default ('t1.micro'). Settings in the facet override those in the server, and settings in the server override those of its facet. You economically describe only what's significant about each machine.

The facets are described and scale independently. If you'd like to add more webnodes, just increase the instance count. If a machine misbehaves, just terminate it. Running `knife cluster launch awesome webnode` will note which machines are missing, and launch and configure them appropriately.

### Advanced clusters remain simple

Let's say that app is truly awesome, and the features and demand increases. This cluster adds an [ElasticSearch server](http://elasticsearch.org) for searching, a haproxy loadbalancer, and spreads the webnodes across two availability zones.

```ruby
ClusterChef.cluster 'demoweb' do
  cloud(:ec2) do
    image_name          "maverick"
    flavor              "t1.micro"
    availability_zones  ['us-east-1a']
  end

  # The database server
  facet :dbnode do
    instances           1
    role                :mysql_server
    cloud do
      flavor           'm1.large'
      backing          'ebs'
    end

    volume(:data) do
      size              20
      keep              true                        
      device            '/dev/sdi'                  
      mount_point       '/data'              
      snapshot_id       'snap-a10234f'             
    end
    server(0).volume(:data){ volume_id('vol-1254') }
  end

  facet :webnode do
    instances           6
    cloud.availability_zones  ['us-east-1a', 'us-east-1b']

    role                :nginx_server
    role                :awesome_webapp
    role                :elasticsearch_client

    volume(:server_logs) do
      size              5                           
      keep              true                        
      device            '/dev/sdi'                  
      mount_point       '/server_logs'              
      snapshot_id       'snap-d9c1edb1'             
    end
    %w[ vol-1234 vol-4321 vol-234a vol-9879 vol-3423 vol-1233 ].each_with_index do |vol_name, idx|
      server(idx).volume(:server_logs){ volume_id(vol_name) }
    end
  end

  facet :esnode do
    instances           1
    role                "elasticsearch_data_esnode"
    role                "elasticsearch_http_esnode"
    cloud.flavor        "m1.large"
  end

  facet :loadbalancer do
    instances           1
    role                "haproxy"
    cloud.flavor        "m1.xlarge"
    elastic_ip          "128.69.69.23"
  end
  
  cluster_role.override_attributes({
    :elasticsearch => {
      :version => '0.17.8',
    },
  })
end
```

ClusterChef speaks naturally to both Chef and your cloud provider. The esnode's `cluster_role.override_attributes` statement will be synchronized to the chef server, pinning the elasticsearch version across the clients and server.. Your chef roles should focus system-specific information; the cluster file lets you see the architecture as a whole.

With these simple settings, if you have already [set up chef's knife to launch cloud servers](http://wiki.opscode.com/display/chef/Launch+Cloud+Instances+with+Knife), typing `knife cluster launch demosimple --bootstrap` will (using Amazon EC2 as an example):

* Synchronize to the chef server:
  - create chef roles on the server for the cluster and each facet.
  - apply role directives (eg the homebase's `default_attributes` declaration).
  - create a node for each machine
  - apply the runlist to each node 
* Set up security isolation:
  - uses a keypair (login ssh key) isolated to that cluster
  - Recognizes the `ssh` role, and add a security group `ssh` that by default opens port 22.
  - Recognize the `nfs_server` role, and adds security groups `nfs_server` and `nfs_client`
  - Authorizes the `nfs_server` to accept connections from all `nfs_client`s. Machines in other clusters that you mark as `nfs_client`s can connect to the NFS server, but are not automatically granted any other access to the machines in this cluster. ClusterChef's opinionated behavior is about more than saving you effort -- tying this behavior to the chef role means you can't screw it up. 
* Launches the machines in parallel:
  - using the image name and the availability zone, it determines the appropriate region, image ID, and other implied behavior. 
  - passes a JSON-encoded user_data hash specifying the machine's chef `node_name` and client key. An appropriately-configured machine image will need no further bootstrapping -- it will connect to the chef server with the appropriate identity and proceed completely unattended.
* Syncronizes to the cloud provider:
  - Applies EC2 tags to the machine, making your console intelligible: ![AWS Console screenshot](https://github.com/infochimps/cluster_chef/raw/version_3/notes/aws_console_screenshot.jpg)
  - Connects external (EBS) volumes, if any, to the correct mount point
  - Associates an elastic IP, if any, to the machine
* Bootstraps the machine using knife bootstrap


## Philosophy

Some general principles of how we use chef.

* *Chef server is never the repository of truth* -- it only mirrors the truth.
  - a file is tangible and immediate to access
* Specifically, we want truth to live in the git repo, and be enforced by the chef server. *There is no truth but git, and chef is its messenger*.
  - this means that everything is versioned, documented and exchangeable.
* *Systems, services and significant modifications cluster should be obvious from the `clusters` file*.  I don't want to have to bounce around nine different files to find out which thing installed a redis:server.
  - basically, the existence of anything that opens a port should be obvious when I look at the cluster file.
* *Roles define systems, clusters assemble systems into a machine*.
  - For example, a resque worker queue has a redis, a webserver and some config files -- your cluster should invoke a @whatever_queue@ role, and the @whatever_queue@ role should include recipes for the component services.
  - the existence of anything that opens a port _or_ runs as a service should be obvious when I look at the roles file.
* *include_recipe considered harmful* Do NOT use include_recipe for anything that a) provides a service, b) launches a daemon or c) is interesting in any way. (so: @include_recipe java@ yes; @include_recipe iptables@ no.) You should note the dependency in the metadata.rb. This seems weird, but the breaking behavior is purposeful: it makes you explicitly state all dependencies.
* It's nice when *machines are in full control of their destiny*.
  - initial setup (elastic IP, attaching a drive) is often best enforced externally
  - but machines should be ablt independently assert things like load balancer registration that that might change at any point in the lifetime.
* It's even nicer, though, to have *full idempotency from the command line*: I can at any time push truth from the git repo to the chef server and know that it will take hold.


---------------------------------------------------------------------------

## Getting Started

This assumes you have installed chef, have a working chef server, and have an AWS account. If you can run knife and use the web browser to see your EC2 console, you can start here. If not, see the instructions below.

### Setup

```ruby
bundle install
```

#### Knife setup

In your <code>$DOT_CHEF_DIR/knife.rb</code>, modify the cookbook path (to include cluster_chef/cookbooks and cluster_chef/site-cookbooks) and to add settings for @cluster_chef_path@, @cluster_path@ and @keypair_path@. Here's mine:

```
        current_dir = File.dirname(__FILE__)
        organization  = 'CHEF_ORGANIZATION'
        username      = 'CHEF_USERNAME'

        # The full path to your cluster_chef installation
        cluster_chef_path File.expand_path("#{current_dir}/../cluster_chef")
        # The list of paths holding clusters
        cluster_path      [ File.expand_path("#{current_dir}/../clusters") ]
        # The directory holding your cloud keypairs
        keypair_path      File.expand_path(current_dir)

        log_level                :info
        log_location             STDOUT
        node_name                username
        client_key               "#{keypair_path}/#{username}.pem"
        validation_client_name   "#{organization}-validator"
        validation_key           "#{keypair_path}/#{organization}-validator.pem"
        chef_server_url          "https://api.opscode.com/organizations/#{organization}"
        cache_type               'BasicFile'
        cache_options( :path => "#{ENV['HOME']}/.chef/checksums" )

        # The first things have lowest priority (so, site-cookbooks gets to win)
        cookbook_path            [
          "#{cluster_chef_path}/cookbooks",
          "#{current_dir}/../cookbooks",
          "#{current_dir}/../site-cookbooks",
        ]

        # If you primarily use AWS cloud services:
        knife[:ssh_address_attribute] = 'cloud.public_hostname'
        knife[:ssh_user] = 'ubuntu'

        # Configure bootstrapping
        knife[:bootstrap_runs_chef_client] = true
        bootstrap_chef_version   "~> 0.10.0"

        # AWS access credentials
        knife[:aws_access_key_id]      = "XXXXXXXXXXX"
        knife[:aws_secret_access_key]  = "XXXXXXXXXXXXX"
```

#### Push to chef server

To send all the cookbooks and role to the chef server, visit your cluster_chef directory and run:

```ruby
        cd $CHEF_REPO_DIR
        mkdir -p $CHEF_REPO_DIR/site-cookbooks
        knife cookbook upload --all
        for foo in roles/*.rb ; do knife role from file $foo & sleep 1 ; done
```

You should see all the cookbooks defined in cluster_chef/cookbooks (ant, apt, ...) listed among those it uploads.

### Your first cluster

Let's create a cluster called 'demosimple'. It's, well, a simple demo cluster.

#### Create a simple demo cluster

Create a directory for your clusters; copy the demosimple cluster and its associated roles from cluster_chef:

```ruby
        mkdir -p $CHEF_REPO_DIR/clusters
        cp cluster_chef/clusters/{defaults,demosimple}.rb ./clusters/
        cp cluster_chef/roles/{big_package,nfs_*,ssh,base_role,chef_client}.rb  ./roles/
        for foo in roles/*.rb ; do knife role from file $foo ; done
```

Symlink in the cookbooks you'll need, and upload them to your chef server:

```ruby
        cd $CHEF_REPO_DIR/cookbooks
        ln -s         ../cluster_chef/site-cookbooks/{nfs,big_package,cluster_chef,cluster_service_discovery,firewall,motd}         .
        knife cookbook upload nfs big_package cluster_chef cluster_service_discovery firewall motd
```

#### AWS credentials

Make a cloud keypair, a secure key for communication with Amazon AWS cloud. cluster_chef expects a keypair named after its cluster -- this is a best practice that helps keep your environments distinct.

1. Log in to the "AWS console":http://bit.ly/awsconsole and create a new keypair named @demosimple@. Your browser will download the private key file.
2. Move the private key file you just downloaded to your .chef dir, and make it private key unsnoopable, or ssh will complain:

```ruby
mv ~/downloads/demosimple.pem $DOT_CHEF_DIR/demosimple.pem
chmod 600 $DOT_CHEF_DIR/*.pem
```

### Cluster chef knife commands

#### knife cluster launch

Hooray! You're ready to launch a cluster:

```ruby
    knife cluster launch demosimple homebase --bootstrap
</pre>

It will kick off a node and then bootstrap it. You'll see it install a whole bunch of things. Yay.

## Extended Installation Notes

### Set up Knife on your local machine, and a Chef Server in the cloud

If you already have a working chef installation you can skip this section.

To get started with knife and chef, follow the "Chef Quickstart,":http://wiki.opscode.com/display/chef/Quick+Start We use the hosted chef service and are very happy, but there are instructions on the wiki to set up a chef server too. Stop when you get to "Bootstrap the Ubuntu system" -- cluster chef is going to make that much easier.

### Cloud setup

If you can use the normal knife bootstrap commands to launch a machine, you can skip this step.

Steps:

* sign up for an AWS account
* Follow the "Knife with AWS quickstart": on the opscode wiki.

Right now cluster chef works well with AWS.  If you're interested in modifying it to work with other cloud providers, "see here":https://github.com/infochimps/cluster_chef/issues/28 or get in touch.