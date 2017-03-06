import boto3
import logging


def get_instance_data(instance_id, region='eu-west-1'):
    """
    Returns instance data for given instance id.
    :param instance_id:
    :param region:
    :return: dict
    """
    ec2 = boto3.client('ec2', region)

    return ec2.describe_instances(InstanceIds=[instance_id])['Reservations'][0]['Instances'][0]


def update_dns_record(name, value, zone_id, action='update', type='CNAME', ttl=30, comment=''):
    """
    Updates Route53 dns record. Allowed actions are: create, delete, update.
    :param name:
    :param value:
    :param zone_id:
    :param action:
    :param type:
    :param ttl:
    :param comment:
    :return: boolean
    """
    action_map = {
        'create': 'CREATE',
        'delete': 'DELETE',
        'update': 'UPSERT',
    }

    try:
        action_translated = action_map[action.lower()]
    except KeyError:
        logging.error("Action '{}' not allowed. Using 'update' instead".format(action))
        action_translated = 'UPSERT'

    route53 = boto3.client('route53')

    domain = route53.get_hosted_zone(Id=zone_id)['HostedZone']['Name']
    name = '{}.{}'.format(name, domain)

    update = {
                'Action': action_translated,
                'ResourceRecordSet': {
                    'Name': name,
                    'Type': type,
                    'TTL': ttl,
                    'ResourceRecords': [
                        {
                            'Value': value
                        }
                    ],
                },
            }

    response = route53.change_resource_record_sets(
        HostedZoneId=zone_id,
        ChangeBatch={
            'Comment': comment,
            'Changes': [update],
        }
    )

    return response['ChangeInfo']['Status'] in ['PENDING', 'INSYNC']
