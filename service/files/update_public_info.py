import aws
import logging
import yaml

_ASG_LAUNCH_EVENT = 'EC2 Instance Launch Successful'
_CNAME = 'CNAME'


def handler(event=None, context=None):
    """
    Event handler for AWS Lambda.
    :param event:
    :param context:
    :return:
    """
    with open('settings.yml', 'r') as f:
        config = yaml.safe_load(f)

    event_type = event['detail-type']
    instance_id = event['detail']['EC2InstanceId']

    logging.info('Received event {} for instance {}'.format(event_type, instance_id))

    if event_type == _ASG_LAUNCH_EVENT:
        update_dns(instance_id=instance_id, zone_id=config['zone_id'], region=config['region'])
    else:
        logging.error('Event "{}" not allowed'.format(event_type))


def update_dns(instance_id, zone_id, region='eu-west-1'):
    """
    Updates dns entry.
    :param instance_id:
    :param zone_id:
    :param region:
    :return:
    """
    instance = aws.get_instance_data(instance_id, region)

    cnames = [tag for tag in instance['Tags'] if tag.get('Key') == _CNAME]
    names = [tag['Value'] for tag in cnames if 'Value' in tag]
    if not names:
        logging.error("No %s tag found.".format(_CNAME))
        return False

    status = aws.update_dns_record(name=names[0], value=instance['PublicDnsName'], zone_id=zone_id)
    logging.info('Status of updating DNS entry was {}'.format('successful' if status else 'unsuccessful'))
