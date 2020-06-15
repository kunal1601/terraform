# configure the provider
provider "aws" {
  region     = "ap-south-1"
  profile    = "lw2" 
} 

# creating a key pair
resource "tls_private_key" "key" {
  algorithm = "RSA"
  rsa_bits = 4096
}
resource "aws_key_pair" "new_key" {
 key_name = "lw_key"
 public_key = tls_private_key.key.public_key_openssh

depends_on = [
    tls_private_key.key
]
}

# saving key to local file
resource "local_file" "foo" {
    content  = tls_private_key.key.private_key_pem
    filename = "C:/Users/user/Desktop/terra/code/lw_key.pem"
    file_permission = "0400"
}

# creating a Security group
resource "aws_security_group" "shield" {
  name        = "shield"
  description = "Allow TLS inbound traffic" 

 ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    description = "HHTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }  

  tags = {
    Name = "shield"
  }
}

# launching an ec2 instance
resource "aws_instance" "my_os" {
   depends_on = [
        aws_security_group.shield,
        tls_private_key.key,
   ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.new_key.key_name
  security_groups = ["shield"]

 tags = {
    Name = "new_os"
  }

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.key.private_key_pem}"
    host     = aws_instance.my_os.public_ip
  }
 
  provisioner "remote-exec" {
     inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      
    ]
  }

}

# create an ebs volume
resource "aws_ebs_volume" "new_ebs" {
  availability_zone = aws_instance.my_os.availability_zone
  size              = 1

  tags = {
    Name = "new_volume"
  }
}

# attaching the ebs volume
resource "aws_volume_attachment" "new_ebs_att" {
  device_name = "/dev/sdh"
  volume_id   =  aws_ebs_volume.new_ebs.id
  instance_id =  aws_instance.my_os.id
  force_detach = true
}

#configuration and mounting
resource "null_resource" "nulllocal3" {
   depends_on = [
        aws_volume_attachment.new_ebs_att,
  ]
    connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.key.private_key_pem}"
    host     = aws_instance.my_os.public_ip
  }
  
   provisioner "remote-exec" {
          inline = [
             "sudo mkfs.ext4 /dev/xvdh",
             "sudo mount /dev/xvdh /var/www/html",
             "sudo rm -rf /var/www/html/*",
             "sudo git clone https://github.com/kunal1601/terraform.git /var/www/html"
     ]
          
    }
}

output "IP_of_instance" {
  value = aws_instance.my_os.public_ip
}

#download github repo to loacl-system
resource "null_resource" "nulllocal32"  {
 provisioner "local-exec" {
    command = "git clone https://github.com/kunal1601/terraform.git  C:/Users/user/Desktop/terra/repo"
    when    = destroy
  }
}

#Creating S3 bucket
resource "aws_s3_bucket" "new_bucket" {
  bucket = "just-relax"
  acl    = "public-read"
}

#Uploading file to S3 bucket
resource "aws_s3_bucket_object" "calm" {
  depends_on = [ aws_s3_bucket.new_bucket,
                 null_resource.nulllocal32,
]
  bucket = "${aws_s3_bucket.new_bucket.id}"
  key    = "one"
  source = "C:/Users/user/Desktop/terra/repo/terraform.jpg"
  acl = "public-read"
  content_type = "image/jpg"

}

resource "aws_cloudfront_origin_access_identity" "o" {
  comment = "this is OAI"
}

#Creating Cloud-front and attaching S3 bucket to it
resource "aws_cloudfront_distribution" "CDN" {
    origin {
        domain_name = aws_s3_bucket.new_bucket.bucket_domain_name
        origin_id   = "S3-just-relax"

        s3_origin_config {
           origin_access_identity = aws_cloudfront_origin_access_identity.o.cloudfront_access_identity_path
       }
    }
       
    enabled = true
    is_ipv6_enabled     = true

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-just-relax"

        forwarded_values {
            query_string = false
        
            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    restrictions {
        geo_restriction {
            restriction_type = "none"
        }
    }

    viewer_certificate {
        cloudfront_default_certificate = true
    }
 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.key.private_key_pem}"
    host     = aws_instance.my_os.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo su << EOF",
      "echo \"<img src='https://${self.domain_name}/${aws_s3_bucket_object.calm.key}'>\" >> /var/www/html/index.html",
      "EOF"
    ]
  }
    
    depends_on = [
        aws_s3_bucket_object.calm
    ]
provisioner "local-exec" {
    command = "start chrome ${aws_instance.my_os.public_ip}"
  }
}
